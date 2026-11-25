import Foundation
import Observation
import os

/// Errores de escritura de la configuración (mensajes en español).
public enum ConfigError: Error, LocalizedError, Equatable {
  case createDirectory(code: Int32)
  case write(code: Int32)
  case unreadable(reason: String)
  case tooLarge

  public var errorDescription: String? {
    switch self {
    case .createDirectory(let code):
      String(
        localized: "The configuration folder couldn’t be created (error \(code)).", bundle: .localized,
        comment:
          "Error shown when Settings can't write the configuration; the placeholder is the error code."
      )
    case .write(let code):
      String(
        localized: "The configuration couldn’t be saved (error \(code)).", bundle: .localized,
        comment:
          "Error shown when Settings can't write the configuration; the placeholder is the error code."
      )
    case .unreadable(let reason):
      String(
        localized: "The configuration can’t be changed: \(reason)", bundle: .localized,
        comment:
          "Error shown when Settings can't write the configuration; the placeholder is the reason.")
    case .tooLarge:
      String(
        localized: "The configuration would exceed the 64 KB limit.", bundle: .localized,
        comment: "Error shown when Settings can't write the configuration.")
    }
  }
}

/// Fuente única de los ajustes: lee, escribe y vigila `~/.config/macterminal/config`.
@MainActor @Observable
public final class ConfigStore {
  public private(set) var config: TerminalConfig = .defaults
  public private(set) var issues: [ConfigIssue] = []
  @ObservationIgnored public var onChange: ((TerminalConfig) -> Void)?
  @ObservationIgnored public var onIssues: (([ConfigIssue]) -> Void)?

  @ObservationIgnored private let fileURL: URL
  @ObservationIgnored private let debounce: Duration
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  /// Se invoca al terminar cada recarga (para tests).
  @ObservationIgnored var onReloaded: (() -> Void)?
  @ObservationIgnored private var sources: [String: DispatchSourceFileSystemObject] = [:]
  @ObservationIgnored private var debounceTask: Task<Void, Never>?
  @ObservationIgnored private var watching = false
  @ObservationIgnored private var wasDeleted = false
  @ObservationIgnored private var existedBefore = false
  private static let logger = Logger(
    subsystem: "com.aitorgarcia.Macterminal", category: "config")

  /// Carga la configuración actual de forma síncrona (archivo ≤ 64 KB, sin bloquear en FIFOs).
  /// `sleep` es el planificador del antirrebote; los tests inyectan uno controlable.
  public init(
    fileURL: URL, debounce: Duration = .milliseconds(150),
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.fileURL = fileURL
    self.debounce = debounce
    self.sleep = sleep
    let (newConfig, newIssues) = evaluate()
    config = newConfig
    issues = newIssues
  }

  isolated deinit {
    for source in sources.values { source.cancel() }
    debounceTask?.cancel()
  }

  private var resolvedPath: String { Self.resolve(fileURL) }
  /// Número de evaluaciones del archivo (para comprobar el antirrebote en tests).
  @ObservationIgnored private(set) var evaluationCount = 0

  /// Sigue la cadena de enlaces del último componente con `readlink` (también si el destino
  /// aún no existe) y resuelve los enlaces del directorio contenedor.
  nonisolated static func resolve(_ url: URL) -> String {
    var path = url.path
    for _ in 0..<16 {
      var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
      let length = readlink(path, &buffer, buffer.count - 1)
      guard length > 0 else { break }
      let target = String(
        decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
      path =
        target.hasPrefix("/")
        ? target
        : ((path as NSString).deletingLastPathComponent as NSString)
          .appendingPathComponent(target)
    }
    let resolved = URL(fileURLWithPath: path)
    return resolved.deletingLastPathComponent().resolvingSymlinksInPath()
      .appending(path: resolved.lastPathComponent).path
  }

  // MARK: - API

  public func reload() {
    // Primero los vigilantes: un cambio posterior a la lectura siempre genera un evento.
    if watching { updateWatchers() }
    let (newConfig, newIssues) = evaluate()
    Self.logger.info(
      "Configuration reloaded with \(newIssues.count, privacy: .public) warnings")
    publish(newConfig, newIssues)
    onReloaded?()
  }

  public func set(_ key: ConfigKey, _ value: String) throws {
    try update(createIfMissing: true) { ConfigWriter.setting(key, to: value, in: $0) }
  }

  /// Borra la clave del archivo (vuelve a su valor por defecto). Sin archivo no crea uno.
  public func remove(_ key: ConfigKey) throws {
    try update(createIfMissing: false) { ConfigWriter.removing(key, in: $0) }
  }

  private func update(createIfMissing: Bool, _ edit: (String) -> String) throws {
    let path = resolvedPath
    let existing: String
    switch Self.readFile(at: path) {
    case .missing: existing = ""
    case .text(let text): existing = text
    case .rejected(let reason): throw ConfigError.unreadable(reason: reason)
    }
    let updated = edit(existing)
    let mustCreate = createIfMissing && !FileManager.default.fileExists(atPath: path)
    if updated != existing || mustCreate {
      guard updated.utf8.count <= ConfigParser.maxFileBytes else { throw ConfigError.tooLarge }
      try Self.writeAtomically(updated, to: path)
    }
    reload()
  }

  public func startWatching() {
    guard !watching else { return }
    watching = true
    // Si ni siquiera existe `~/.config`, se crea (0700) para poder vigilarlo.
    let parent = fileURL.deletingLastPathComponent().deletingLastPathComponent().path
    if !FileManager.default.fileExists(atPath: parent) {
      do {
        try FileManager.default.createDirectory(
          atPath: parent, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
      } catch {
        let code = (error as NSError).code
        Self.logger.error("Couldn't create the parent directory (code \(code, privacy: .public))")
      }
    }
    updateWatchers()
    reload()
  }

  public func stopWatching() {
    watching = false
    debounceTask?.cancel()
    debounceTask = nil
    for source in sources.values { source.cancel() }
    sources.removeAll()
  }

  // MARK: - Evaluación

  private func evaluate() -> (TerminalConfig, [ConfigIssue]) {
    evaluationCount += 1
    switch Self.readFile(at: resolvedPath) {
    case .missing:
      let deleted = existedBefore || wasDeleted
      existedBefore = false
      wasDeleted = deleted
      guard deleted else { return (.defaults, []) }
      return (
        .defaults,
        [
          ConfigIssue(
            line: 1, key: nil,
            message: String(
              localized: "The configuration file no longer exists; the default values are used.",
              bundle: .localized,
              comment: "Configuration warning."))
        ]
      )
    case .text(let text):
      existedBefore = true
      wasDeleted = false
      return ConfigParser.parse(text)
    case .rejected(let reason):
      existedBefore = true
      wasDeleted = false
      return (.defaults, [ConfigIssue(line: 1, key: nil, message: reason)])
    }
  }

  private func publish(_ newConfig: TerminalConfig, _ newIssues: [ConfigIssue]) {
    if newConfig != config {
      config = newConfig
      onChange?(newConfig)
    }
    if newIssues != issues {
      issues = newIssues
      onIssues?(newIssues)
    }
  }

  // MARK: - Vigilancia

  private func scheduleReload() {
    debounceTask?.cancel()
    let delay = debounce
    let sleep = sleep
    debounceTask = Task { [weak self] in
      do { try await sleep(delay) } catch { return }
      guard !Task.isCancelled else { return }
      self?.reload()
    }
  }

  /// Vigila los directorios (cubre guardado por renombrado, creación tardía y borrado) y el
  /// propio archivo (cubre ediciones en el sitio). Se reconstruye tras cada recarga.
  private func updateWatchers() {
    var paths: [String: String] = [:]  // clave -> ruta
    for url in [fileURL, URL(fileURLWithPath: resolvedPath)] {
      let directory = Self.deepestExistingDirectory(of: url.deletingLastPathComponent().path)
      paths["dir:\(directory)"] = directory
    }
    var info = stat()
    let filePath = resolvedPath
    if stat(filePath, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG {
      paths["file:\(filePath):\(info.st_ino)"] = filePath
    }

    for (key, source) in sources where paths[key] == nil {
      source.cancel()
      sources[key] = nil
    }
    for (key, path) in paths where sources[key] == nil {
      let fd = open(path, O_EVTONLY | O_CLOEXEC)
      guard fd >= 0 else { continue }
      let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write, .extend, .delete, .rename, .link, .attrib],
        queue: .main)
      source.setEventHandler { [weak self] in
        MainActor.assumeIsolated { self?.scheduleReload() }
      }
      source.setCancelHandler { close(fd) }
      source.resume()
      sources[key] = source
    }
  }

  private static func deepestExistingDirectory(of path: String) -> String {
    var current = path
    while current != "/" {
      var isDirectory: ObjCBool = false
      if FileManager.default.fileExists(atPath: current, isDirectory: &isDirectory),
        isDirectory.boolValue
      {
        return current
      }
      current = (current as NSString).deletingLastPathComponent
    }
    return "/"
  }

  // MARK: - E/S

  enum ReadResult {
    case missing
    case text(String)
    case rejected(String)
  }

  /// Abre sin bloquear, comprueba el tipo sobre el descriptor (sin carrera) y lee ≤ 64 KB.
  nonisolated static func readFile(at path: String) -> ReadResult {
    let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
    guard fd >= 0 else {
      if errno == ENOENT || errno == ENOTDIR { return .missing }
      return .rejected(
        String(
          localized:
            "The configuration can’t be read (error \(errno)); the default values are used.",
          bundle: .localized, comment: "Configuration warning; the placeholder is the errno code."))
    }
    defer { close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
      return .rejected(
        String(
          localized:
            "The configuration path isn’t a regular file; the default values are used.",
          bundle: .localized, comment: "Configuration warning."))
    }
    guard info.st_size <= ConfigParser.maxFileBytes else {
      return .rejected(
        String(
          localized: "The configuration file is larger than 64 KB; the default values are used.",
          bundle: .localized, comment: "Configuration warning."))
    }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    while data.count <= ConfigParser.maxFileBytes {
      let count = read(fd, &buffer, buffer.count)
      if count < 0 {
        if errno == EINTR { continue }
        return .rejected(
          String(
            localized:
              "The configuration can’t be read (error \(errno)); the default values are used.",
            bundle: .localized, comment: "Configuration warning; the placeholder is the errno code."))
      }
      if count == 0 { break }
      data.append(contentsOf: buffer[0..<count])
    }
    guard data.count <= ConfigParser.maxFileBytes else {
      return .rejected(
        String(
          localized: "The configuration file is larger than 64 KB; the default values are used.",
          bundle: .localized, comment: "Configuration warning."))
    }
    guard let text = String(data: data, encoding: .utf8) else {
      return .rejected(
        String(
          localized:
            "The configuration file isn’t valid UTF-8; the default values are used.",
          bundle: .localized, comment: "Configuration warning."))
    }
    return .text(text)
  }

  /// Escritura atómica: temporal 0600 en el mismo directorio + `rename`. Conserva el modo del
  /// destino si ya existía. `path` ya viene sin symlinks, así que el enlace original sigue intacto.
  nonisolated static func writeAtomically(_ text: String, to path: String) throws {
    let directory = (path as NSString).deletingLastPathComponent
    do {
      try FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw ConfigError.createDirectory(code: Int32((error as NSError).code))
    }
    var existing = stat()
    let mode: mode_t = stat(path, &existing) == 0 ? existing.st_mode & 0o7777 : 0o600
    let temporary = "\(directory)/.config.\(UUID().uuidString).tmp"
    let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw ConfigError.write(code: errno) }
    var failure: Int32?
    let bytes = Array(text.utf8)
    var offset = 0
    while offset < bytes.count, failure == nil {
      let written = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
      if written < 0 {
        if errno != EINTR { failure = errno }
      } else {
        offset += written
      }
    }
    if failure == nil, fchmod(fd, mode) != 0 { failure = errno }
    if failure == nil, fsync(fd) != 0 { failure = errno }
    close(fd)
    if failure == nil, rename(temporary, path) != 0 { failure = errno }
    if let failure {
      unlink(temporary)
      throw ConfigError.write(code: failure)
    }
  }
}
