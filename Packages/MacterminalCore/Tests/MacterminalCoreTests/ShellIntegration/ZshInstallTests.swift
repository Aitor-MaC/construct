import Foundation
import Testing

@testable import MacterminalCore

@Suite struct ZshInstallTests {
  @Test func createsPrivateDirectoryAndFiles() throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let zdotdir = try ZshIntegration.install(in: base.url)
    #expect(zdotdir.lastPathComponent == "macterminal-zsh-\(getuid())")
    #expect(try permissions(of: zdotdir) == 0o700)
    for name in ZshScripts.files.map(\.name) {
      #expect(try permissions(of: zdotdir.appending(path: name)) == 0o600)
    }
  }

  @Test func installIsIdempotentAndWritesCurrentScripts() throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let first = try ZshIntegration.install(in: base.url)
    try Data("stale".utf8).write(to: first.appending(path: ".zshenv"))
    let second = try ZshIntegration.install(in: base.url)
    #expect(first == second)
    for file in ZshScripts.files {
      let written = try String(contentsOf: second.appending(path: file.name), encoding: .utf8)
      #expect(written == file.contents)
    }
  }

  @Test func concurrentInstallsLeaveCompleteFilesOnly() async throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let url = base.url
    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<16 {
        group.addTask { _ = try ZshIntegration.install(in: url) }
      }
      try await group.waitForAll()
    }
    let zdotdir = url.appending(path: "macterminal-zsh-\(getuid())")
    let entries = try FileManager.default.contentsOfDirectory(atPath: zdotdir.path)
    #expect(Set(entries) == Set(ZshScripts.files.map(\.name)))
    for file in ZshScripts.files {
      let written = try String(contentsOf: zdotdir.appending(path: file.name), encoding: .utf8)
      #expect(written == file.contents)
    }
  }

  @Test func rejectsSymlinkInPlaceOfDirectory() throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let target = base.url.appending(path: "elsewhere")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(
      at: base.url.appending(path: "macterminal-zsh-\(getuid())"), withDestinationURL: target)
    #expect(throws: ZshIntegrationError.notADirectory) {
      try ZshIntegration.install(in: base.url)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
  }

  @Test func rejectsDirectoryWithWiderPermissions() throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let zdotdir = base.url.appending(path: "macterminal-zsh-\(getuid())")
    try FileManager.default.createDirectory(
      at: zdotdir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
    #expect(throws: ZshIntegrationError.insecurePermissions(mode: 0o755)) {
      try ZshIntegration.install(in: base.url)
    }
  }

  @Test func rejectsDirectoryOwnedBySomeoneElse() throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let zdotdir = base.url.appending(path: "owned")
    try FileManager.default.createDirectory(
      at: zdotdir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    #expect(throws: ZshIntegrationError.notOwned) {
      try ZshIntegration.openPrivateDirectory(at: zdotdir, owner: getuid() + 1)
    }
  }

  @Test func everyScriptPassesSyntaxCheck() throws {
    let base = try TemporaryDirectory()
    defer { base.remove() }
    let zdotdir = try ZshIntegration.install(in: base.url)
    for name in ZshScripts.files.map(\.name) {
      let result = try runZshSyntaxCheck(zdotdir.appending(path: name))
      #expect(result.status == 0, "\(name): \(result.errors)")
    }
  }

  @Test func environmentCarriesOptionsAndNonce() {
    let zdotdir = URL(filePath: "/tmp/a b/macterminal-zsh-501")
    let env = ZshIntegration.environment(
      zdotdir: zdotdir, userZdotdir: URL(filePath: "/Users/x/.config/zsh"),
      options: PromptOptions(prompt: false, autosuggest: true), nonce: "0123456789abcdef0123456789abcdef")
    #expect(env["ZDOTDIR"] == "/tmp/a b/macterminal-zsh-501")
    #expect(env["MACTERMINAL_USER_ZDOTDIR"] == "/Users/x/.config/zsh")
    #expect(env["MACTERMINAL_PROMPT"] == "0")
    #expect(env["MACTERMINAL_AUTOSUGGEST"] == "1")
    #expect(env["MACTERMINAL_NONCE"] == "0123456789abcdef0123456789abcdef")
    #expect(env["TERM_PROGRAM"] == "Construct")
    let withoutUserDir = ZshIntegration.environment(
      zdotdir: zdotdir, userZdotdir: nil, options: PromptOptions(prompt: true, autosuggest: false),
      nonce: "0123456789abcdef0123456789abcdef")
    #expect(withoutUserDir["MACTERMINAL_USER_ZDOTDIR"] == nil)
    #expect(withoutUserDir["MACTERMINAL_PROMPT"] == "1")
    #expect(withoutUserDir["MACTERMINAL_AUTOSUGGEST"] == "0")
  }

  private func permissions(of url: URL) throws -> Int {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { throw POSIXError(.ENOENT) }
    return Int(info.st_mode & 0o777)
  }

  private func runZshSyntaxCheck(_ script: URL) throws -> (status: Int32, errors: String) {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/zsh")
    process.arguments = ["-n", script.path]
    let errors = Pipe()
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return (process.terminationStatus, text)
  }
}

struct TemporaryDirectory {
  let url: URL
  init() throws {
    url = FileManager.default.temporaryDirectory.appending(path: "mt zsh \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
  }
  /// A shell's background workers can still be writing inside while the tree is removed, which
  /// fails the removal (EPERM, ENOTEMPTY); it is retried for a while, with every entry made
  /// writable, before it counts as a failure.
  func remove() {
    var lastError: (any Error)?
    for attempt in 0..<20 {
      if attempt > 0 {
        usleep(50_000)
        makeWritable()
      }
      do {
        try FileManager.default.removeItem(at: url)
        return
      } catch {
        lastError = error
      }
    }
    Issue.record("no se pudo limpiar \(url.path): \(String(describing: lastError))")
  }

  private func makeWritable() {
    let entries = FileManager.default.enumerator(atPath: url.path)?.compactMap { $0 as? String }
    for path in [url.path] + (entries ?? []).map({ url.appending(path: $0).path }) {
      chmod(path, S_IRWXU)
    }
  }
}
