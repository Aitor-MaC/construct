import Foundation
import Synchronization
import Testing

@testable import MacterminalCore

/// Real interactive zsh in a pseudo-terminal (`/usr/bin/script`) with a fake HOME, fed through
/// the integration produced by `ZshIntegration.install` and `environment`.
final class ZshSession {
  let home: URL
  let sessionNonce = SessionNonce.random()
  var nonce: String { sessionNonce.hex }
  private let base: TemporaryDirectory
  private let process = Process()
  private let input = Pipe()
  private let output = OutputBuffer()

  init(
    options: PromptOptions = PromptOptions(prompt: true, autosuggest: true),
    zshrc: String = "", zshenv: String? = nil, columns: Int = 120, userZdotdir: String? = nil,
    environmentOverrides: [String: String] = [:], prepareHome: (URL) throws -> Void = { _ in }
  ) throws {
    let base = try TemporaryDirectory()
    self.base = base
    // zsh reports the physical path (/private/var/...), which Foundation's resolution hides.
    let physicalBase = try #require(realpath(base.url.path, nil))
    defer { free(physicalBase) }
    let home = URL(filePath: String(cString: physicalBase)).appending(path: "home")
    self.home = home
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false)
    let rcDirectory = userZdotdir.map { home.appending(path: $0) } ?? home
    try FileManager.default.createDirectory(at: rcDirectory, withIntermediateDirectories: true)
    try Data(zshrc.utf8).write(to: rcDirectory.appending(path: ".zshrc"))
    if let zshenv { try Data(zshenv.utf8).write(to: rcDirectory.appending(path: ".zshenv")) }
    try prepareHome(home)
    let zdotdir = try ZshIntegration.install(in: base.url)
    var environment = ZshIntegration.environment(
      zdotdir: zdotdir, userZdotdir: userZdotdir == nil ? nil : rcDirectory,
      options: options, nonce: nonce)
    environment["HOME"] = home.path
    environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
    environment["TERM"] = "xterm-256color"
    environment["LANG"] = "en_US.UTF-8"
    environment["COLUMNS"] = String(columns)
    environment["LINES"] = "40"
    environment["SHELL"] = "/bin/zsh"
    environment["USER"] = NSUserName()
    environment.merge(environmentOverrides) { _, override in override }
    process.executableURL = URL(filePath: "/usr/bin/script")
    process.arguments = ["-q", "/dev/null", "/bin/zsh", "-il"]
    process.environment = environment
    process.currentDirectoryURL = home
    process.standardInput = input
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    let buffer = output
    pipe.fileHandleForReading.readabilityHandler = { handle in buffer.append(handle.availableData) }
    try process.run()
  }

  /// Exits the shell so it finishes writing its files before the fake HOME is removed.
  deinit {
    send("\u{15}exit\r")
    let deadline = Date().addingTimeInterval(3)
    while process.isRunning, Date() < deadline { usleep(20_000) }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
    }
    base.remove()
  }

  var bytes: [UInt8] { output.snapshot }

  func send(_ text: String) {
    input.fileHandleForWriting.write(Data(text.utf8))
  }

  /// Authenticated 7777 marks in arrival order, without the nonce: `A`, `B`, `C;…`, `D;0`, …
  var marks: [String] { Self.marks(in: bytes, nonce: nonce) }

  func waitUntil(timeout: Duration = .seconds(10), _ condition: (ZshSession) -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
      if condition(self) { return true }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return condition(self)
  }

  /// Waits for the prompt number `count` (1-based) to be fully drawn.
  func waitForPrompt(_ count: Int, timeout: Duration = .seconds(10)) async -> Bool {
    await waitUntil(timeout: timeout) { $0.marks.filter { $0 == "B" }.count >= count }
  }

  func run(_ command: String) async -> Bool {
    let prompts = marks.filter { $0 == "A" }.count
    send(command + "\r")
    return await waitUntil { session in
      session.marks.filter { $0 == "A" }.count > prompts
        && session.marks.last(where: { $0 == "A" || $0 == "B" }) == "B"
    }
  }

  static func marks(in bytes: [UInt8], nonce: String) -> [String] {
    let prefix = Array("\u{1b}]7777;\(nonce);".utf8)
    var result: [String] = []
    var index = 0
    while let start = bytes[index...].firstRange(of: prefix) {
      guard let end = bytes[start.upperBound...].firstIndex(of: 0x07) else { break }
      result.append(String(decoding: bytes[start.upperBound..<end], as: UTF8.self))
      index = end
    }
    return result
  }

  /// What the last command printed: from the end of its `C` mark to the `133;D` that closes it.
  var lastCommandOutput: String? {
    let text = self.text
    guard let command = text.range(of: "\u{1b}]7777;\(nonce);C;", options: .backwards),
      let start = text[command.upperBound...].firstIndex(of: "\u{07}"),
      let end = text.range(of: "\u{1b}]133;D", range: start..<text.endIndex)
    else { return nil }
    return String(text[text.index(after: start)..<end.lowerBound])
  }

  static func decodeBase64(_ text: Substring) -> String? {
    Data(base64Encoded: String(text)).map { String(decoding: $0, as: UTF8.self) }
  }

  var text: String { String(decoding: bytes, as: UTF8.self) }
}

final class OutputBuffer: Sendable {
  private let storage = Mutex<[UInt8]>([])
  func append(_ data: Data) { storage.withLock { $0.append(contentsOf: data) } }
  var snapshot: [UInt8] { storage.withLock { $0 } }
}
