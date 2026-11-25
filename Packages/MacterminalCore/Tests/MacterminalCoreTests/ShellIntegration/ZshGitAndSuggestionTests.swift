import Foundation
import Testing

@testable import MacterminalCore

@Suite struct ZshGitAndSuggestionTests {
  /// Background colour of the git segment (#123D20) as emitted by zsh.
  static let gitSegment = "\u{1b}[48;2;18;61;32m"

  /// The fake git does not `exec`: its `sleep` child also holds the output pipe, so killing only
  /// git would leave it running for the full 5 s.
  @Test func slowGitNeverDelaysThePromptAndIsKilledWithItsChildren() async throws {
    let session = try ZshSession(zshrc: "path=($HOME/fakebin $path)\ncd ~/repo") { home in
      try GitFixture.repository(at: home.appending(path: "repo"), home: home, branch: "main")
      let pidFile = home.appending(path: "child.pids").path
      try Self.installFakeTool(
        "git", in: home, script: "/bin/sleep 5 &\necho $! >> '\(pidFile)'\nwait\n")
    }
    let pidFile = session.home.appending(path: "child.pids")
    #expect(await session.waitForPrompt(1))

    // Minimum of three prompts: parallel tests only add noise, never remove latency.
    var latencies: [Duration] = []
    var started = ContinuousClock.now
    for _ in 0..<3 {
      started = ContinuousClock.now
      #expect(await session.run("true"))
      latencies.append(ContinuousClock.now - started)
    }
    #expect(try #require(latencies.min()) < .milliseconds(300), "\(latencies)")

    // Each prompt starts git in the background; wait until all four runs have registered.
    func startedPids() -> [Int32] {
      Self.lines(of: pidFile).compactMap { Int32($0) }
    }
    #expect(await session.waitUntil(timeout: .seconds(1)) { _ in startedPids().count >= 4 })
    let pids = startedPids()
    let gone = await session.waitUntil(timeout: .milliseconds(3500)) { _ in
      pids.allSatisfy { kill($0, 0) != 0 }
    }
    #expect(gone, "git's children must die with it after 2 s, well before their 5 s sleep ends")
    #expect(ContinuousClock.now - started < .seconds(4))
    #expect(!session.text.contains(Self.gitSegment))
  }

  /// Without job control the worker shares the shell's process group: the timeout must not take
  /// the interactive shell down with git.
  @Test func gitTimeoutWithoutJobControlKeepsTheShellAlive() async throws {
    let zshrc = "path=($HOME/fakebin $path)\ncd ~/repo\nunsetopt monitor"
    let session = try ZshSession(zshrc: zshrc) { home in
      try GitFixture.repository(at: home.appending(path: "repo"), home: home, branch: "main")
      let pidFile = home.appending(path: "git.pid").path
      try Self.installFakeTool("git", in: home, script: "echo $$ > '\(pidFile)'\nexec /bin/sleep 5\n")
    }
    let pidFile = session.home.appending(path: "git.pid")
    #expect(await session.waitForPrompt(1))
    // Waits for the kill itself, not for a fixed time: under load the watchdog may fire late.
    // The generous timeout is only a safeguard; the sleep would end on its own after 5 s.
    #expect(await session.waitUntil(timeout: .seconds(4.5)) { _ in Self.lines(of: pidFile).count == 1 })
    let git = try #require(Self.lines(of: pidFile).first.flatMap { Int32($0) })
    #expect(await session.waitUntil(timeout: .seconds(4.5)) { _ in kill(git, 0) != 0 })
    #expect(await session.run("print -r -- still-$((6 * 7))"))
    #expect(session.text.contains("still-42"))
  }

  @Test func gitRunsOnlyInsideRepositories() async throws {
    let session = try ZshSession(zshrc: "path=($HOME/fakebin $path)") { home in
      let repository = home.appending(path: "repo")
      try GitFixture.repository(at: repository, home: home, branch: "main")
      try FileManager.default.createDirectory(
        at: repository.appending(path: "sub"), withIntermediateDirectories: false)
      let calls = home.appending(path: "git.calls").path
      try Self.installFakeTool("git", in: home, script: "echo \"$PWD\" >> '\(calls)'\n")
    }
    let calls = session.home.appending(path: "git.calls")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(await session.run("cd repo"))
    #expect(await session.run("cd sub"))
    #expect(await session.waitUntil { _ in Self.lines(of: calls).count >= 2 })
    // Both workers run concurrently, so their calls may land in either order.
    let repository = session.home.appending(path: "repo").path
    let recorded = Self.lines(of: calls)
    #expect(recorded.count == 2, "\(recorded)")
    #expect(Set(recorded) == [repository, repository + "/sub"])
  }

  /// Without Command Line Tools, /usr/bin/git is a shim that opens the install dialog every time
  /// it runs: the developer directory is checked once per shell and git is never started.
  @Test(arguments: [false, true])
  func systemGitRunsOnlyWithDeveloperTools(installed: Bool) async throws {
    let session = try ZshSession(zshrc: "path=($HOME/fakebin $path)\ncd ~/repo") { home in
      try GitFixture.repository(at: home.appending(path: "repo"), home: home, branch: "main")
      let calls = home.appending(path: "xcode-select.calls").path
      let answer = installed ? "exec /usr/bin/xcode-select \"$@\"" : "exit 2"
      try Self.installFakeTool("xcode-select", in: home, script: "echo $* >> '\(calls)'\n\(answer)\n")
    }
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(await session.run("true"))
    // Absence needs a fixed window; presence returns as soon as it shows, so its timeout is lax.
    let window: Duration = installed ? .seconds(10) : .milliseconds(1500)
    let shown = await session.waitUntil(timeout: window) { $0.text.contains(Self.gitSegment) }
    #expect(shown == installed)
    #expect(Self.lines(of: session.home.appending(path: "xcode-select.calls")) == ["-p"])
  }

  private static func installFakeTool(_ name: String, in home: URL, script: String) throws {
    let fakeBin = home.appending(path: "fakebin")
    try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
    let tool = fakeBin.appending(path: name)
    try Data("#!/bin/sh\n\(script)".utf8).write(to: tool)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
  }

  private static func lines(of file: URL) -> [String] {
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").map(String.init)
  }

  @Test func gitSegmentAppearsOnRepaintOnlyInsideRepository() async throws {
    let session = try ZshSession { home in
      try GitFixture.repository(at: home.appending(path: "repo"), home: home, branch: "main")
    }
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(!session.text.contains(Self.gitSegment))
    #expect(await session.run("cd repo"))
    let shown = await session.waitUntil { $0.text.contains(Self.gitSegment) && $0.text.contains("\u{1b}[38;2;156;255;180m main ±1 ") }
    #expect(shown)
    // Cached per directory: the next prompt is drawn with the segment before git answers again.
    #expect(await session.run("true"))
    let text = session.text
    let lastPrompt = try #require(text.range(of: "7777;\(session.nonce);A", options: .backwards))
    let firstDraw = try #require(text.range(of: "7777;\(session.nonce);B", range: lastPrompt.upperBound..<text.endIndex))
    #expect(text[lastPrompt.upperBound..<firstDraw.lowerBound].contains(Self.gitSegment))
  }

  @Test func suggestionComesFromMostRecentHistoryAndArrowAcceptsIt() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("echo alpha1"))
    #expect(await session.run("echo alpha2"))
    let typedAt = session.bytes.count
    session.send("echo al")
    let suggested = await session.waitUntil {
      String(decoding: $0.bytes[typedAt...], as: UTF8.self).contains("pha2")
    }
    #expect(suggested)
    #expect(await session.run("\u{1b}[C"))
    #expect(lastCommand(session) == "echo alpha2")
  }

  @Test func controlFAcceptsSuggestion() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("echo bravo"))
    session.send("echo br")
    #expect(await session.run("\u{06}"))
    #expect(lastCommand(session) == "echo bravo")
  }

  @Test func disabledAutosuggestionShowsAndAcceptsNothing() async throws {
    let session = try ZshSession(options: PromptOptions(prompt: true, autosuggest: false))
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("echo charlie"))
    let typedAt = session.bytes.count
    session.send("echo ch")
    #expect(await session.run("\u{06}"))
    #expect(lastCommand(session) == "echo ch")
    #expect(!String(decoding: session.bytes[typedAt...], as: UTF8.self).contains("arlie"))
  }

  private func lastCommand(_ session: ZshSession) -> String? {
    session.marks.last { $0.hasPrefix("C;") }.flatMap { ZshSession.decodeBase64($0.dropFirst(2)) }
  }
}
