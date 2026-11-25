import Foundation
import Testing

@testable import MacterminalCore

/// Cuenta eventos y permite esperarlos con tope de tiempo (sin sleeps fijos).
@MainActor
final class Signal {
  private(set) var total = 0
  private var pending = 0
  private var waiter: CheckedContinuation<Bool, Never>?

  func fire() {
    total += 1
    if let waiter {
      self.waiter = nil
      waiter.resume(returning: true)
    } else {
      pending += 1
    }
  }

  /// El tope es solo una salvaguarda: con éxito se retorna al instante, sin depender de la carga.
  func wait(timeout: Duration = .seconds(30)) async -> Bool {
    if pending > 0 {
      pending -= 1
      return true
    }
    let timer = Task { [weak self] in
      do { try await Task.sleep(for: timeout) } catch { return }
      guard let self, let waiter = self.waiter else { return }
      self.waiter = nil
      waiter.resume(returning: false)
    }
    let result = await withCheckedContinuation { waiter = $0 }
    timer.cancel()
    return result
  }
}

/// Planificador del antirrebote controlado por el test: cada `sleep` queda suspendido hasta
/// `release()`; los cancelados terminan lanzando `CancellationError`.
actor ManualSleeper {
  private var nextID = 0
  private var sleepers: [Int: CheckedContinuation<Void, Error>] = [:]
  private var cancelled: Set<Int> = []
  private(set) var requests = 0
  private var waiters: [(above: Int, continuation: CheckedContinuation<Void, Never>)] = []

  func sleep() async throws {
    let id = nextID
    nextID += 1
    requests += 1
    let ready = waiters.filter { requests > $0.above }
    waiters.removeAll { requests > $0.above }
    for waiter in ready { waiter.continuation.resume() }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        if cancelled.remove(id) != nil {
          continuation.resume(throwing: CancellationError())
        } else {
          sleepers[id] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancel(id) }
    }
  }

  private func cancel(_ id: Int) {
    if let continuation = sleepers.removeValue(forKey: id) {
      continuation.resume(throwing: CancellationError())
    } else {
      cancelled.insert(id)
    }
  }

  /// Espera a que `requests` supere `count`.
  func waitForRequests(above count: Int) async {
    if requests > count { return }
    await withCheckedContinuation { waiters.append((count, $0)) }
  }

  /// Deja terminar los `sleep` aún vivos (los no cancelados).
  func release() {
    let all = sleepers
    sleepers.removeAll()
    for continuation in all.values { continuation.resume() }
  }
}

struct TempDir {
  let url: URL
  init() throws {
    url = FileManager.default.temporaryDirectory.appending(
      path: "macterminal-config-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  func remove() { try? FileManager.default.removeItem(at: url) }
}

@MainActor
@Suite("ConfigStore")
struct ConfigStoreTests {
  func permissions(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1
  }

  @Test func missingFileGivesDefaultsWithoutIssues() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let store = ConfigStore(fileURL: dir.url.appending(path: "a/b/config"))
    #expect(store.config == .defaults)
    #expect(store.issues.isEmpty)
  }

  @Test func firstSetCreatesDirectoryAndFileWith0600() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "macterminal/config")
    let store = ConfigStore(fileURL: file)
    try store.set(.fontSize, "17")
    #expect(store.config.fontSize == 17)
    #expect(try permissions(file) == 0o600)
    #expect(try permissions(file.deletingLastPathComponent()) == 0o700)
    #expect(try String(contentsOf: file, encoding: .utf8) == "font-size = 17\n")
  }

  @Test func setKeepsCommentsAndExistingPermissions() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    try "# hola\nfoo = 1\n".write(to: file, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
    let store = ConfigStore(fileURL: file)
    try store.set(.prompt, "false")
    #expect(try String(contentsOf: file, encoding: .utf8) == "# hola\nfoo = 1\nprompt = false\n")
    #expect(try permissions(file) == 0o644)
    #expect(!store.config.prompt)
    // Sin restos de temporales.
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
    #expect(names == ["config"])
  }

  @Test func setRoundTripsThroughParser() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    let store = ConfigStore(fileURL: file)
    try store.set(.fontFamily, "Fira Code")
    try store.set(.intensity, "inmersivo")
    let reloaded = ConfigStore(fileURL: file)
    #expect(reloaded.config.fontFamily == "Fira Code")
    #expect(reloaded.config.intensity == .inmersivo)
    #expect(reloaded.issues.isEmpty)
  }

  @Test func setOnDirectoryPathThrowsAReadableError() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let store = ConfigStore(fileURL: dir.url)  // es un directorio
    #expect(throws: ConfigError.self) { try store.set(.prompt, "false") }
    #expect(store.issues.count == 1)
  }

  @Test func oversizedFileIsRejectedWithIssue() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    let text = "font-size = 20\n# " + String(repeating: "a", count: 100 * 1024)
    try text.write(to: file, atomically: true, encoding: .utf8)
    let store = ConfigStore(fileURL: file)
    #expect(store.config == .defaults)
    #expect(store.issues.count == 1)
  }

  @Test func fifoGivesIssueWithoutBlocking() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    #expect(mkfifo(file.path, 0o600) == 0)
    let store = ConfigStore(fileURL: file)
    #expect(store.config == .defaults)
    #expect(store.issues.count == 1)
    #expect(throws: ConfigError.self) { try store.set(.prompt, "false") }
  }

  @Test func inPlaceExternalEditReloads() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
    let store = ConfigStore(fileURL: file)
    let changed = Signal()
    store.onChange = { _ in changed.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data("font-size = 20\n".utf8))
    try handle.close()
    #expect(await changed.wait())
    #expect(store.config.fontSize == 20)
  }

  @Test func atomicRenameSaveReloads() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
    let store = ConfigStore(fileURL: file)
    let changed = Signal()
    store.onChange = { _ in changed.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    let temp = dir.url.appending(path: ".config.swp")
    try "font-size = 18\n".write(to: temp, atomically: false, encoding: .utf8)
    #expect(rename(temp.path, file.path) == 0)
    // Sin tope corto: `wait` vuelve en cuanto llega el evento, y con --parallel el hilo principal
    // puede tardar más de 1 s en atender la fuente de despacho.
    #expect(await changed.wait())
    #expect(store.config.fontSize == 18)
    // Segunda edición por renombrado: el archivo vigilado cambió de inodo.
    try "font-size = 19\n".write(to: temp, atomically: false, encoding: .utf8)
    #expect(rename(temp.path, file.path) == 0)
    #expect(await changed.wait())
    #expect(store.config.fontSize == 19)
  }

  @Test func deletingFileReturnsToDefaultsWithIssue() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
    let store = ConfigStore(fileURL: file)
    let issues = Signal()
    store.onIssues = { _ in issues.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    try FileManager.default.removeItem(at: file)
    #expect(await issues.wait())
    #expect(store.config == .defaults)
    #expect(store.issues.count == 1)
  }

  @Test(.timeLimit(.minutes(2))) func burstOfWritesNotifiesOnce() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    try "font-size = 12\n".write(to: file, atomically: true, encoding: .utf8)
    let sleeper = ManualSleeper()
    let store = ConfigStore(fileURL: file, sleep: { _ in try await sleeper.sleep() })
    let changed = Signal()
    let reloaded = Signal()
    store.onChange = { _ in changed.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    store.onReloaded = { reloaded.fire() }
    let baseline = store.evaluationCount
    // Cada escritura distinta genera un evento que reinicia el antirrebote; el reloj no avanza.
    // Un único `write(2)` en el sitio (mismo tamaño, sin truncar) da exactamente un evento: con
    // truncado + escritura, un segundo evento tardío podía llegar después de `release()`,
    // cancelar la recarga liberada y dejar otra espera que nadie liberaba.
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    for size in 13...17 {
      let seen = await sleeper.requests
      try handle.seek(toOffset: 0)
      try handle.write(contentsOf: Data("font-size = \(size)\n".utf8))
      await sleeper.waitForRequests(above: seen)
      #expect(store.config.fontSize == 12)
      #expect(store.evaluationCount == baseline)
    }
    await sleeper.release()  // vence el antirrebote
    #expect(await reloaded.wait())
    #expect(store.config.fontSize == 17)
    #expect(store.evaluationCount == baseline + 1)
    #expect(changed.total == 1)
  }

  @Test func danglingSymlinkIsKeptAndTargetCreated() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let target = dir.url.appending(path: "dotfiles/config")  // la carpeta tampoco existe
    let link = dir.url.appending(path: "config")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let store = ConfigStore(fileURL: link)
    try store.set(.fontSize, "15")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try String(contentsOf: target, encoding: .utf8) == "font-size = 15\n")
    #expect(store.config.fontSize == 15)
  }

  @Test func relativeSymlinkChainIsFollowed() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    try FileManager.default.createDirectory(
      at: dir.url.appending(path: "d"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      atPath: dir.url.appending(path: "b").path, withDestinationPath: "d/real")
    try FileManager.default.createSymbolicLink(
      atPath: dir.url.appending(path: "a").path, withDestinationPath: "b")
    let store = ConfigStore(fileURL: dir.url.appending(path: "a"))
    try store.set(.prompt, "false")
    #expect(
      try String(contentsOf: dir.url.appending(path: "d/real"), encoding: .utf8)
        == "prompt = false\n")
    #expect(!store.config.prompt)
  }

  @Test func setDoesNotCreateWriterWatcherLoop() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "macterminal/config")
    let store = ConfigStore(fileURL: file)
    let changed = Signal()
    store.onChange = { _ in changed.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    try store.set(.fontSize, "15")
    #expect(await changed.wait())
    #expect(await changed.wait(timeout: .milliseconds(600)) == false)
    #expect(changed.total == 1)
  }

  @Test func symlinkIsPreservedAndTargetEditedAndWatched() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let target = dir.url.appending(path: "dotfiles/config")
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "# destino\nfont-size = 12\n".write(to: target, atomically: true, encoding: .utf8)
    let link = dir.url.appending(path: "config")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let store = ConfigStore(fileURL: link)
    #expect(store.config.fontSize == 12)
    try store.set(.fontSize, "16")
    #expect(
      try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
    #expect(try String(contentsOf: target, encoding: .utf8) == "# destino\nfont-size = 16\n")

    let changed = Signal()
    store.onChange = { _ in changed.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    try "font-size = 21\n".write(to: target, atomically: true, encoding: .utf8)
    #expect(await changed.wait())
    #expect(store.config.fontSize == 21)
  }

  @Test func configCreatedAfterStartIsLoaded() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: ".config/macterminal/config")
    try FileManager.default.createDirectory(
      at: dir.url.appending(path: ".config"), withIntermediateDirectories: true)
    let store = ConfigStore(fileURL: file)
    let changed = Signal()
    store.onChange = { _ in changed.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "font-size = 22\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(await changed.wait())
    #expect(store.config.fontSize == 22)
    // Una edición posterior (ya con el directorio recién creado) también se ve.
    try "font-size = 23\n".write(to: file, atomically: false, encoding: .utf8)
    #expect(await changed.wait())
    #expect(store.config.fontSize == 23)
  }

  @Test func startWatchingCreatesMissingParentWith0700() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "nuevo/macterminal/config")
    let store = ConfigStore(fileURL: file)
    store.startWatching()
    defer { store.stopWatching() }
    #expect(try permissions(dir.url.appending(path: "nuevo")) == 0o700)
  }

  @Test func invalidValuesPublishIssues() async throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    let store = ConfigStore(fileURL: file)
    let issues = Signal()
    store.onIssues = { _ in issues.fire() }
    store.startWatching()
    defer { store.stopWatching() }
    try "background-opacity = 0\n".write(to: file, atomically: true, encoding: .utf8)
    #expect(await issues.wait())
    #expect(store.config.backgroundOpacity == 0.5)
    #expect(store.issues.count == 1)
  }
}
