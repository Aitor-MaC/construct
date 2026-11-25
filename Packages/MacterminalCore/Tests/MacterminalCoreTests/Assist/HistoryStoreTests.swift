import Darwin
import Foundation
import Testing

@testable import MacterminalCore

/// Directorio temporal exclusivo por test; se borra al soltarlo.
private final class HistoryTempDir: @unchecked Sendable {
  let url: URL
  init() {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("macterminal-history-\(UUID().uuidString)", isDirectory: true)
  }
  var file: URL { url.appendingPathComponent("sub/history.json") }
  deinit { try? FileManager.default.removeItem(at: url) }
}

private func permissions(_ url: URL) throws -> Int {
  let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
  return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ seconds: Int) -> Date { t0.addingTimeInterval(Double(seconds)) }

@Suite("HistoryStore")
struct HistoryStoreTests {
  @Test func dedupesMovesToFrontAndCounts() async throws {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    for i in 0..<3 { await store.record(command: "ls -la", cwd: URL(filePath: "/tmp/\(i)"), at: at(i)) }
    await store.record(command: "pwd", cwd: nil, at: at(10))
    await store.record(command: "ls -la", cwd: URL(filePath: "/last"), at: at(20))
    let recent = await store.recentCommands(limit: 10)
    #expect(recent.map(\.command) == ["ls -la", "pwd"])
    #expect(recent[0].count == 4)
    #expect(recent[0].cwd == URL(filePath: "/last"))
    #expect(recent[0].lastUsed == at(20))
  }

  @Test func threeRecordsGiveOneEntryWithCountThree() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    for i in 0..<3 { await store.record(command: "make", cwd: nil, at: at(i)) }
    let recent = await store.recentCommands(limit: 10)
    #expect(recent.count == 1)
    #expect(recent[0].count == 3)
  }

  @Test("ignora vacíos, espacio inicial y peticiones #", arguments: [
    "", "   ", "\n", " secret", "\tsecret", "# cómo listo archivos", "#nota",
  ])
  func ignoresExcluded(command: String) async throws {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    await store.record(command: command, cwd: nil, at: t0)
    #expect(await store.recentCommands(limit: 10).isEmpty)
    try await store.flush()
    if FileManager.default.fileExists(atPath: dir.file.path) {
      let text = try String(contentsOf: dir.file, encoding: .utf8)
      #expect(text.range(of: "secret") == nil)
    }
  }

  @Test func limitKeepsTheMostRecent() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file, limit: 3)
    _ = await store.load()
    for i in 1...5 { await store.record(command: "cmd\(i)", cwd: nil, at: at(i)) }
    let recent = await store.recentCommands(limit: 10)
    #expect(recent.map(\.command) == ["cmd5", "cmd4", "cmd3"])
  }

  @Test func recentLimitsAreRespected() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    for i in 1...5 { await store.record(command: "cmd\(i)", cwd: nil, at: at(i)) }
    #expect(await store.recentCommands(limit: 2).count == 2)
    #expect(await store.recentCommands(limit: 0).isEmpty)
    #expect(await store.recentCommands(limit: -1).isEmpty)
  }

  @Test func persistsAcrossInstancesAfterFlush() async throws {
    let dir = HistoryTempDir()
    let first = HistoryStore(fileURL: dir.file)
    _ = await first.load()
    await first.record(command: "git status", cwd: URL(filePath: "/work"), at: at(1))
    await first.recordDirectory(URL(filePath: "/work"), at: at(1))
    try await first.flush()
    #expect(FileManager.default.fileExists(atPath: dir.file.path))

    let second = HistoryStore(fileURL: dir.file)
    #expect(await second.load() == nil)
    let recent = await second.recentCommands(limit: 5)
    #expect(recent.map(\.command) == ["git status"])
    #expect(recent[0].cwd == URL(filePath: "/work"))
    #expect(recent[0].lastUsed == at(1))
    #expect(await second.recentDirectories(limit: 5) == [URL(filePath: "/work")])
  }

  @Test func directoriesAreSeparateFromEntries() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file, limit: 1)
    _ = await store.load()
    await store.recordDirectory(URL(filePath: "/a"), at: at(1))
    await store.record(command: "ls", cwd: URL(filePath: "/a"), at: at(1))
    await store.recordDirectory(URL(filePath: "/b"), at: at(2))
    await store.record(command: "ls", cwd: URL(filePath: "/b"), at: at(2))
    await store.record(command: "pwd", cwd: URL(filePath: "/b"), at: at(3))  // expulsa "ls"
    #expect(await store.recentCommands(limit: 10).map(\.command) == ["pwd"])
    #expect(await store.recentDirectories(limit: 10) == [URL(filePath: "/b"), URL(filePath: "/a")])
  }

  @Test func directoriesAreUniqueMostRecentFirstAndCapped() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    for i in 0..<250 { await store.recordDirectory(URL(filePath: "/d\(i)"), at: at(i)) }
    await store.recordDirectory(URL(filePath: "/d100"), at: at(300))
    let dirs = await store.recentDirectories(limit: 1000)
    #expect(dirs.count == 200)
    #expect(dirs.first == URL(filePath: "/d100"))
    #expect(Set(dirs).count == 200)
    #expect(await store.recentDirectories(limit: 3).count == 3)
  }

  @Test func versionOneFileWithoutDirectoriesLoadsWithoutError() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let json = """
      {"version":1,"future":"ignored","entries":[{"command":"ls","extra":true}]}
      """
    try Data(json.utf8).write(to: dir.file)
    let store = HistoryStore(fileURL: dir.file)
    #expect(await store.load() == nil)
    let recent = await store.recentCommands(limit: 5)
    #expect(recent.map(\.command) == ["ls"])
    #expect(recent[0].cwd == nil)
    #expect(recent[0].count == 1)
    #expect(await store.recentDirectories(limit: 5).isEmpty)
  }

  @Test func garbageFileIsMovedAsideAndStoreStartsEmpty() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("esto no es json {{{".utf8).write(to: dir.file)
    let store = HistoryStore(fileURL: dir.file)
    let error = await store.load()
    #expect(error != nil)
    #expect(error?.errorDescription?.isEmpty == false)
    #expect(await store.recentCommands(limit: 5).isEmpty)
    let corrupt = dir.file.appendingPathExtension("corrupt")
    #expect(FileManager.default.fileExists(atPath: corrupt.path))
    #expect(!FileManager.default.fileExists(atPath: dir.file.path))

    await store.record(command: "ls", cwd: nil, at: t0)
    try await store.flush()
    #expect(try permissions(dir.file) == 0o600)
  }

  @Test func secondCorruptFileGetsTimestampedName() async throws {
    let dir = HistoryTempDir()
    let folder = dir.file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: dir.file.appendingPathExtension("corrupt"))
    try Data("nuevo basura".utf8).write(to: dir.file)
    let store = HistoryStore(fileURL: dir.file, now: { at(42) })
    #expect(await store.load() != nil)
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    #expect(names.filter { $0.hasPrefix("history.json.corrupt") }.count == 2)
    #expect(try String(contentsOf: dir.file.appendingPathExtension("corrupt"), encoding: .utf8) == "old")
  }

  @Test func fileOverFourMegabytesIsMovedAside() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x20, count: 5 * 1024 * 1024).write(to: dir.file)
    let store = HistoryStore(fileURL: dir.file)
    #expect(await store.load() != nil)
    #expect(FileManager.default.fileExists(atPath: dir.file.appendingPathExtension("corrupt").path))
    #expect(await store.recentCommands(limit: 5).isEmpty)
  }

  @Test func unsupportedFutureVersionIsReportedNotOverwritten() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version":99,"entries":[]}"#.utf8).write(to: dir.file)
    let store = HistoryStore(fileURL: dir.file)
    #expect(await store.load() == .unsupportedVersion(99))
    #expect(FileManager.default.fileExists(atPath: dir.file.appendingPathExtension("corrupt").path))
  }

  @Test func fileIsCreatedWith0600AndDirectoryIsCreated() async throws {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    await store.record(command: "ls", cwd: nil, at: t0)
    try await store.flush()
    #expect(try permissions(dir.file) == 0o600)
  }

  @Test func permissionsAreReappliedAfterEveryWrite() async throws {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    await store.record(command: "ls", cwd: nil, at: t0)
    try await store.flush()
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: dir.file.path)
    await store.record(command: "pwd", cwd: nil, at: at(1))
    try await store.flush()
    #expect(try permissions(dir.file) == 0o600)
  }

  @Test func burstOfRecordsWritesOnceWhenTheWaitEnds() async throws {
    let dir = HistoryTempDir()
    let gate = SleepGate()
    let store = HistoryStore(fileURL: dir.file, sleep: { _ in try await gate.wait() })
    _ = await store.load()
    for i in 0..<20 { await store.record(command: "cmd\(i)", cwd: nil, at: at(i)) }
    #expect(!FileManager.default.fileExists(atPath: dir.file.path))
    await eventually { gate.started >= 1 }
    #expect(gate.started == 1)  // una sola espera para toda la ráfaga

    gate.release()
    await eventually { FileManager.default.fileExists(atPath: dir.file.path) }
    let reloaded = HistoryStore(fileURL: dir.file)
    #expect(await reloaded.load() == nil)
    #expect(await reloaded.recentCommands(limit: 100).count == 20)

    // Una nueva ráfaga programa otra escritura (la anterior ya terminó).
    try FileManager.default.removeItem(at: dir.file)
    await store.record(command: "after", cwd: nil, at: at(99))
    await eventually { FileManager.default.fileExists(atPath: dir.file.path) }
    #expect(gate.started == 2)
  }

  @Test func backgroundWriteFailureReachesOnError() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(at: dir.file, withIntermediateDirectories: true)
    let gate = SleepGate()
    let errors = ErrorBox()
    let store = HistoryStore(
      fileURL: dir.file, sleep: { _ in try await gate.wait() }, onError: { errors.append($0) })
    _ = await store.load()  // el "archivo" es un directorio: se aparta y se puede escribir
    try FileManager.default.createDirectory(at: dir.file, withIntermediateDirectories: true)
    await store.record(command: "ls", cwd: nil, at: t0)
    gate.release()
    await eventually { !errors.all.isEmpty }
    guard case .writeFailed = errors.all.first else {
      Issue.record("se esperaba .writeFailed, llegó \(String(describing: errors.all.first))")
      return
    }
  }

  @Test func flushWithScheduledWritePendingWritesOnlyOnce() async throws {
    let dir = HistoryTempDir()
    let gate = SleepGate()
    let store = HistoryStore(fileURL: dir.file, sleep: { _ in try await gate.wait() })
    _ = await store.load()
    await store.record(command: "ls", cwd: nil, at: t0)
    try await store.flush()
    #expect(FileManager.default.fileExists(atPath: dir.file.path))
    await eventually { gate.ended == 1 }  // la espera cancelada por flush terminó

    try FileManager.default.removeItem(at: dir.file)
    gate.release()
    for _ in 0..<50 { await Task.yield() }
    #expect(!FileManager.default.fileExists(atPath: dir.file.path))
  }

  @Test func unreadableHistoryIsNeverOverwrittenWhenItCannotBeSetAside() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("[\"original\"]".utf8).write(to: dir.file)  // corrupto: habrá que apartarlo
    // Sin permiso de escritura en el directorio no se puede renombrar.
    let folder = dir.file.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
    let store = HistoryStore(fileURL: dir.file)
    let error = await store.load()
    guard case .unreadable = error else {
      Issue.record("se esperaba .unreadable, llegó \(String(describing: error))")
      return
    }
    let message: String = error?.errorDescription ?? ""
    #expect(!message.contains("copia"))
    await store.record(command: "ls", cwd: nil, at: t0)
    try await store.flush()
    #expect(await store.recentCommands(limit: 5).map(\.command) == ["ls"])  // sigue en memoria
    #expect(try Data(contentsOf: dir.file) == Data("[\"original\"]".utf8))
  }

  @Test func unreadableFileIsNeverOverwritten() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{\"version\":1,\"entries\":[{\"command\":\"keep\"}]}".utf8).write(to: dir.file)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.file.path) }
    let store = HistoryStore(fileURL: dir.file)
    guard case .unreadable = await store.load() else {
      Issue.record("se esperaba .unreadable")
      return
    }
    await store.record(command: "ls", cwd: nil, at: t0)
    try await store.flush()
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dir.file.path)
    #expect(try String(contentsOf: dir.file, encoding: .utf8).contains("keep"))
  }

  @Test func symlinkToHugeFileIsSetAsideNotFollowed() async throws {
    let dir = HistoryTempDir()
    let folder = dir.file.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let target = folder.appendingPathComponent("huge.bin")
    try Data(count: 5 * 1024 * 1024).write(to: target)
    try FileManager.default.createSymbolicLink(at: dir.file, withDestinationURL: target)
    let store = HistoryStore(fileURL: dir.file)
    #expect(await store.load() == .corrupt)
    #expect(await store.recentCommands(limit: 5).isEmpty)
    #expect(try Data(contentsOf: target).count == 5 * 1024 * 1024)  // destino intacto
    #expect(!FileManager.default.fileExists(atPath: dir.file.path))  // el enlace se apartó
  }

  @Test func fifoIsRejectedWithoutBlocking() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(mkfifo(dir.file.path, 0o600) == 0)
    let store = HistoryStore(fileURL: dir.file)
    #expect(await store.load() == .corrupt)
    #expect(await store.recentCommands(limit: 5).isEmpty)
  }

  @Test func fileGrowingBeyondTheCapIsReadAsTooLarge() async throws {
    let dir = HistoryTempDir()
    try FileManager.default.createDirectory(
      at: dir.file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0x20, count: HistoryStore.maxReadBytes + 1).write(to: dir.file)
    let store = HistoryStore(fileURL: dir.file)
    #expect(await store.load() == .tooLarge)
  }

  @Test func fiftyConcurrentRecordsLoseNothing() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    await withTaskGroup(of: Void.self) { group in
      for i in 0..<50 {
        group.addTask { await store.record(command: "cmd\(i)", cwd: nil, at: at(i)) }
      }
    }
    let recent = await store.recentCommands(limit: 100)
    #expect(recent.count == 50)
    #expect(Set(recent.map(\.command)).count == 50)
  }

  @Test func oversizedEntryIsNotStored() async {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    await store.record(command: String(repeating: "x", count: 17 * 1024), cwd: nil, at: t0)
    await store.record(command: "ok", cwd: nil, at: t0)
    #expect(await store.recentCommands(limit: 10).map(\.command) == ["ok"])
    #expect(await store.droppedOversizeCount == 1)
  }

  @Test func fullHistoryStaysUnderTwoMegabytesAndReloads() async throws {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    let filler = String(repeating: "á\"\\\t€🙂", count: 4096 / 14)  // ~4 KB con escapes y Unicode
    for i in 0..<2000 {
      await store.record(command: "\(i) \(filler)", cwd: URL(filePath: "/work/\(i)"), at: at(i))
    }
    try await store.flush()
    let size = try Data(contentsOf: dir.file).count
    #expect(size <= 2 * 1024 * 1024)
    #expect(size > 1024 * 1024)

    let reloaded = HistoryStore(fileURL: dir.file)
    #expect(await reloaded.load() == nil)
    let recent = await reloaded.recentCommands(limit: 5)
    #expect(recent.count == 5)
    #expect(recent[0].command.hasPrefix("1999 "))
    #expect(recent[0].command.contains("\"\\\t"))
  }

  @Test func unreadablePathReportsErrorWithoutLeakingPath() async throws {
    let dir = HistoryTempDir()
    // El "archivo" es un directorio: no se puede leer.
    try FileManager.default.createDirectory(at: dir.file, withIntermediateDirectories: true)
    let store = HistoryStore(fileURL: dir.file)
    let error = await store.load()
    #expect(error != nil)
    let message: String = error?.errorDescription ?? ""
    #expect(message.range(of: dir.url.path) == nil)
  }

  @Test func flushFailureIsThrown() async throws {
    let dir = HistoryTempDir()
    let store = HistoryStore(fileURL: dir.file)
    _ = await store.load()
    try FileManager.default.createDirectory(at: dir.file, withIntermediateDirectories: true)
    await store.record(command: "ls", cwd: nil, at: t0)
    await #expect(throws: HistoryError.self) { try await store.flush() }
  }
}

/// Espera controlada por el test: `wait()` queda pendiente hasta `release()`; si la cancelan, lanza.
private final class SleepGate: @unchecked Sendable {
  private let lock = NSLock()
  private var startedCount = 0
  private var endedCount = 0
  private let stream: AsyncStream<Void>
  private let source: AsyncStream<Void>.Continuation

  init() {
    (stream, source) = AsyncStream<Void>.makeStream()
  }

  var started: Int { lock.withLock { startedCount } }
  var ended: Int { lock.withLock { endedCount } }

  func wait() async throws {
    lock.withLock { startedCount += 1 }
    defer { lock.withLock { endedCount += 1 } }
    for await _ in stream { break }
    try Task.checkCancellation()
  }

  func release() { source.finish() }
}

private final class ErrorBox: @unchecked Sendable {
  private let lock = NSLock()
  private var errors: [HistoryError] = []
  func append(_ error: HistoryError) { lock.withLock { errors.append(error) } }
  var all: [HistoryError] { lock.withLock { errors } }
}

/// Espera una condición (con tope) sin depender del reloj para el resultado: falla si nunca se cumple.
private func eventually(_ condition: () async -> Bool) async {
  for _ in 0..<5000 {
    if await condition() { return }
    try? await Task.sleep(for: .milliseconds(1))
  }
  Issue.record("la condición no se cumplió a tiempo")
}
