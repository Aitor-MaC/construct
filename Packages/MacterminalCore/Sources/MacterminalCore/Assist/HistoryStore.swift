import Darwin
import Foundation
import os

/// Una línea del historial de comandos.
public struct HistoryEntry: Codable, Sendable, Equatable {
  public var command: String
  public var cwd: URL?
  public var lastUsed: Date
  public var count: Int

  public init(command: String, cwd: URL? = nil, lastUsed: Date, count: Int = 1) {
    self.command = command
    self.cwd = cwd
    self.lastUsed = lastUsed
    self.count = count
  }

  private enum CodingKeys: String, CodingKey { case command, cwd, lastUsed, count }

  /// Solo `command` es obligatorio; lo ausente toma su valor por defecto y lo desconocido se ignora.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    command = try container.decode(String.self, forKey: .command)
    cwd = try container.decodeIfPresent(URL.self, forKey: .cwd)
    lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed) ?? .distantPast
    count = max(1, try container.decodeIfPresent(Int.self, forKey: .count) ?? 1)
  }
}

/// Errores del historial. Los mensajes están en español y nunca incluyen rutas ni comandos.
public enum HistoryError: Error, LocalizedError, Equatable, Sendable {
  case corrupt
  case tooLarge
  case unsupportedVersion(Int)
  case unreadable(domain: String, code: Int)
  case writeFailed(domain: String, code: Int)

  public var errorDescription: String? {
    switch self {
    case .corrupt:
      String(
        localized:
          "The history was damaged. A copy was set aside (history.json.corrupt) and a new, empty one was started.",
        bundle: .localized,
        comment: "Toast shown at launch when history.json can't be decoded.")
    case .tooLarge:
      String(
        localized:
          "The history was too large. A copy was set aside (history.json.corrupt) and a new, empty one was started.",
        bundle: .localized,
        comment: "Toast shown at launch when history.json exceeds the size limit.")
    case .unsupportedVersion(let version):
      String(
        localized:
          "The history uses a newer format (version \(version)). A copy was set aside and a new, empty one was started.",
        bundle: .localized,
        comment:
          "Toast shown at launch when history.json comes from a newer version; the placeholder is the format version."
      )
    case .unreadable(let domain, let code):
      String(
        localized:
          "The history couldn’t be read or set aside (\(domain) \(code)). It’s kept in memory only and nothing will be saved until the next launch.",
        bundle: .localized,
        comment: "Toast shown at launch; the placeholders are the error domain and code.")
    case .writeFailed(let domain, let code):
      String(
        localized: "The history couldn’t be saved (\(domain) \(code)).", bundle: .localized,
        comment:
          "Toast shown when saving history fails; the placeholders are the error domain and code.")
    }
  }
}

/// Historial local persistente de comandos y carpetas visitadas. Una única instancia por app.
public actor HistoryStore {
  static let currentVersion = 1
  static let maxDirectories = 200
  static let maxFileBytes = 2 * 1024 * 1024
  static let maxReadBytes = 4 * 1024 * 1024
  static let maxEntryBytes = 16 * 1024

  private struct Directory: Codable, Equatable {
    var url: URL
    var lastUsed: Date

    init(url: URL, lastUsed: Date) {
      self.url = url
      self.lastUsed = lastUsed
    }

    private enum CodingKeys: String, CodingKey { case url, lastUsed }

    init(from decoder: Decoder) throws {
      if let single = try? decoder.singleValueContainer(), let url = try? single.decode(URL.self) {
        self.url = url
        self.lastUsed = .distantPast
        return
      }
      let container = try decoder.container(keyedBy: CodingKeys.self)
      url = try container.decode(URL.self, forKey: .url)
      lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed) ?? .distantPast
    }
  }

  private struct FileContents: Codable {
    var version: Int
    var entries: [HistoryEntry]
    var directories: [Directory]

    init(version: Int, entries: [HistoryEntry], directories: [Directory]) {
      self.version = version
      self.entries = entries
      self.directories = directories
    }

    private enum CodingKeys: String, CodingKey { case version, entries, directories }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
      entries = try container.decodeIfPresent([HistoryEntry].self, forKey: .entries) ?? []
      directories = try container.decodeIfPresent([Directory].self, forKey: .directories) ?? []
    }
  }

  private let fileURL: URL
  private let limit: Int
  private let writeInterval: Duration
  private let sleep: @Sendable (Duration) async throws -> Void
  private let now: @Sendable () -> Date
  private let onError: (@Sendable (HistoryError) -> Void)?
  private let log = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "history")

  private var entries: [HistoryEntry] = []  // más reciente primero
  private var directories: [Directory] = []  // más reciente primero
  private var loaded = false
  private var pendingLoadError: HistoryError?
  /// Si el archivo existente no se pudo leer ni apartar, no se escribe encima: solo memoria hasta el próximo arranque.
  private var memoryOnly = false
  private var dirty = false
  private var writeTask: Task<Void, Never>?
  private var writeGeneration = 0

  /// Entradas descartadas por superar `maxEntryBytes` (observable en tests).
  private(set) var droppedOversizeCount = 0

  public init(
    fileURL: URL,
    limit: Int = 2000,
    writeInterval: Duration = .seconds(1),
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    now: @escaping @Sendable () -> Date = { Date() },
    onError: (@Sendable (HistoryError) -> Void)? = nil
  ) {
    self.fileURL = fileURL
    self.limit = max(1, limit)
    self.writeInterval = writeInterval
    self.sleep = sleep
    self.now = now
    self.onError = onError
  }

  // MARK: - API

  /// Carga el archivo. Devuelve el error (corrupto, ilegible…) si lo hubo; el almacén queda utilizable y vacío.
  public func load() -> HistoryError? {
    ensureLoaded()
    defer { pendingLoadError = nil }
    return pendingLoadError
  }

  public func record(command: String, cwd: URL?, at date: Date) {
    ensureLoaded()
    guard let first = command.first, first != " ", first != "\t", first != "#" else { return }
    let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }

    var entry = HistoryEntry(command: text, cwd: cwd, lastUsed: date, count: 1)
    if let index = entries.firstIndex(where: { $0.command == text }) {
      let (next, overflow) = entries[index].count.addingReportingOverflow(1)
      entry.count = overflow ? entries[index].count : next
      entries.remove(at: index)
    }
    guard Self.encodedSize(of: entry) <= Self.maxEntryBytes else {
      droppedOversizeCount += 1
      log.info(
        "History entry dropped for size (total: \(self.droppedOversizeCount, privacy: .public))")
      return
    }
    entries.insert(entry, at: 0)
    if entries.count > limit { entries.removeLast(entries.count - limit) }
    markDirty()
  }

  public func recordDirectory(_ url: URL, at date: Date) {
    ensureLoaded()
    let normalized = url.standardizedFileURL
    directories.removeAll { $0.url.path == normalized.path }
    directories.insert(Directory(url: normalized, lastUsed: date), at: 0)
    if directories.count > Self.maxDirectories {
      directories.removeLast(directories.count - Self.maxDirectories)
    }
    markDirty()
  }

  public func recentCommands(limit: Int) -> [HistoryEntry] {
    ensureLoaded()
    return Array(entries.prefix(max(0, limit)))
  }

  public func recentDirectories(limit: Int) -> [URL] {
    ensureLoaded()
    return directories.prefix(max(0, limit)).map(\.url)
  }

  /// Escribe lo pendiente. T14 lo espera al terminar la app.
  public func flush() async throws {
    ensureLoaded()
    writeTask?.cancel()
    writeTask = nil
    writeGeneration += 1
    guard dirty, !memoryOnly else { return }
    try writeToDisk()
  }

  // MARK: - Escritura coalescida

  private func markDirty() {
    guard !memoryOnly else { return }
    dirty = true
    guard writeTask == nil else { return }
    writeGeneration += 1
    let generation = writeGeneration
    let interval = writeInterval
    let sleep = self.sleep
    writeTask = Task { [weak self] in
      do { try await sleep(interval) } catch { return }
      await self?.scheduledWriteFired(generation: generation)
    }
  }

  private func scheduledWriteFired(generation: Int) {
    guard generation == writeGeneration else { return }
    writeTask = nil
    guard dirty else { return }
    do {
      try writeToDisk()
    } catch let error as HistoryError {
      onError?(error)
    } catch {
      onError?(.writeFailed(domain: (error as NSError).domain, code: (error as NSError).code))
    }
  }

  private func writeToDisk() throws {
    let data = try budgetedData()
    do {
      try Self.atomicWrite(data, to: fileURL)
    } catch let error as HistoryError {
      log.error("Saving the history failed")
      throw error
    } catch {
      let ns = error as NSError
      log.error(
        "Saving the history failed: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)")
      throw HistoryError.writeFailed(domain: ns.domain, code: ns.code)
    }
    dirty = false
  }

  // MARK: - Presupuesto de tamaño

  private static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  private static func encodedSize<T: Encodable>(of value: T) -> Int {
    (try? makeEncoder().encode(value).count) ?? .max
  }

  /// Serializa recortando las entradas más antiguas (y luego las carpetas) hasta caber en 2 MB.
  private func budgetedData() throws -> Data {
    let encoder = Self.makeEncoder()
    func encode() throws -> Data {
      try encoder.encode(
        FileContents(version: Self.currentVersion, entries: entries, directories: directories))
    }
    var data = try encode()
    guard data.count > Self.maxFileBytes else { return data }

    var total = data.count
    while total > Self.maxFileBytes, let last = entries.last {
      total -= Self.encodedSize(of: last) + 1
      entries.removeLast()
    }
    while total > Self.maxFileBytes, let last = directories.last {
      total -= Self.encodedSize(of: last) + 1
      directories.removeLast()
    }
    data = try encode()
    while data.count > Self.maxFileBytes, !(entries.isEmpty && directories.isEmpty) {
      if !entries.isEmpty { entries.removeLast() } else { directories.removeLast() }
      data = try encode()
    }
    log.info("History trimmed to stay within the size budget")
    return data
  }

  /// Escritura atómica: archivo temporal 0600 en el mismo directorio y `rename`. Nunca es legible por otros.
  private static func atomicWrite(_ data: Data, to url: URL) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let temp = directory.appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard fd >= 0 else {
      throw HistoryError.writeFailed(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    do {
      if fchmod(fd, 0o600) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM) }
      try handle.write(contentsOf: data)
      if fsync(fd) != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
      try handle.close()
      if rename(temp.path, url.path) != 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      }
    } catch {
      try? handle.close()
      unlink(temp.path)
      throw error
    }
  }

  // MARK: - Carga

  private func ensureLoaded() {
    guard !loaded else { return }
    loaded = true
    var info = stat()
    guard lstat(fileURL.path, &info) == 0 else { return }
    guard (info.st_mode & S_IFMT) == S_IFREG else {
      // Enlace simbólico, FIFO, dispositivo…: nunca se lee (CWE-400); se aparta el propio nodo.
      reject(.corrupt)
      return
    }
    let data: Data
    do {
      guard let read = try Self.readCapped(fileURL) else {
        reject(.tooLarge)
        return
      }
      data = read
    } catch HistoryError.corrupt {
      reject(.corrupt)
      return
    } catch {
      let ns = error as NSError
      memoryOnly = true
      fail(.unreadable(domain: ns.domain, code: ns.code))
      return
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    guard let contents = try? decoder.decode(FileContents.self, from: data) else {
      reject(.corrupt)
      return
    }
    guard contents.version <= Self.currentVersion else {
      reject(.unsupportedVersion(contents.version))
      return
    }
    entries = Array(contents.entries.prefix(limit))
    directories = Array(contents.directories.prefix(Self.maxDirectories))
  }

  /// Lee como mucho `maxReadBytes`; `nil` si hay más. Sin seguir enlaces y sin bloquear en FIFOs.
  private static func readCapped(_ url: URL) throws -> Data? {
    let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else {
      throw HistoryError.unreadable(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var info = stat()
    guard fstat(fd, &info) == 0 else {
      throw HistoryError.unreadable(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    guard (info.st_mode & S_IFMT) == S_IFREG else { throw HistoryError.corrupt }
    let data = try handle.read(upToCount: maxReadBytes + 1) ?? Data()
    return data.count > maxReadBytes ? nil : data
  }

  /// Aparta el archivo inservible; si no se puede apartar, no se escribirá encima de él.
  private func reject(_ error: HistoryError) {
    if let moveError = moveAside() {
      memoryOnly = true
      let ns = moveError as NSError
      fail(.unreadable(domain: ns.domain, code: ns.code))
    } else {
      fail(error)
    }
  }

  private func fail(_ error: HistoryError) {
    pendingLoadError = error
    switch error {
    case .corrupt: log.error("Corrupt history set aside")
    case .tooLarge: log.error("Oversized history set aside")
    case .unsupportedVersion(let v):
      log.error("History with unsupported version: \(v, privacy: .public)")
    case .unreadable(let domain, let code):
      log.error("Unreadable history: \(domain, privacy: .public) \(code, privacy: .public)")
    case .writeFailed: break
    }
  }

  /// Renombra el archivo a `history.json.corrupt` (con marca de tiempo si ya existe). Devuelve el error si falla.
  private func moveAside() -> Error? {
    let fm = FileManager.default
    var candidate = fileURL.appendingPathExtension("corrupt")
    if fm.fileExists(atPath: candidate.path) {
      let stamp = Int(now().timeIntervalSince1970)
      candidate = fileURL.appendingPathExtension("corrupt.\(stamp)")
      if fm.fileExists(atPath: candidate.path) {
        candidate = fileURL.appendingPathExtension("corrupt.\(stamp)-\(UUID().uuidString)")
      }
    }
    do {
      try fm.moveItem(at: fileURL, to: candidate)
      return nil
    } catch {
      let ns = error as NSError
      log.error(
        "Couldn't set the history aside: \(ns.domain, privacy: .public) \(ns.code, privacy: .public)"
      )
      return error
    }
  }
}
