import Foundation
import Testing

@testable import MacterminalCore

/// B2: names under an attacker's control (directories, branches, user and host names) must never
/// be evaluated by PROMPT_SUBST nor reach the terminal as control sequences.
@Suite struct ZshPromptSafetyTests {
  static let hostileNames = [
    "$(touch pwned)", "`touch pwned`", "%F{red}x", "esc\u{1b}]0;HACKED\u{07}", "bel\u{07}x", "nl\nx",
    "bidi\u{202E}gpj",
  ]

  @Test(arguments: hostileNames)
  func hostileDirectoryNameIsShownInert(_ name: String) async throws {
    let session = try ZshSession(zshrc: "setopt prompt_subst")
    #expect(await session.waitForPrompt(1))
    let directory = session.home.appending(path: name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    // The glob reaches the only directory without typing its control characters.
    #expect(await session.run("cd -- *(/)"))
    #expect(session.text.contains("~/" + Self.visible(name)))
    #expect(await session.run("cd ~"))
    #expect(session.marks.filter { $0.hasPrefix("cwd;") }.contains { mark in
      ZshSession.decodeBase64(mark.dropFirst(4)) == directory.path
    })
    assertInert(session)
  }

  @Test(arguments: ["$(touch${IFS}pwned)", "`id`", "%F{red}x"])
  func hostileBranchNameIsShownInert(_ branch: String) async throws {
    let session = try ZshSession(zshrc: "setopt prompt_subst") { home in
      try GitFixture.repository(at: home.appending(path: "repo"), home: home, branch: branch)
    }
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("cd repo"))
    let shown = await session.waitUntil { $0.text.contains(Self.visible(branch)) }
    #expect(shown, "branch \(branch) not shown")
    assertInert(session)
  }

  /// C4: `$HOST` comes from the network, so it is data too. The user is `$USERNAME`, which zsh
  /// takes from the user ID, so a hostile `$USER` in the environment never reaches the prompt.
  @Test(arguments: hostileNames)
  func hostileUserAndHostAreShownInert(_ name: String) async throws {
    // Read from a file so the rc file itself contains no quoting to get wrong.
    let session = try ZshSession(zshrc: "setopt prompt_subst\nexport USER=$(<~/name)\nHOST=$(<~/name)") {
      home in try Data(name.utf8).write(to: home.appending(path: "name"))
    }
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(session.text.contains(" \(NSUserName())@\(Self.visible(name)) "))
    assertInert(session)
  }

  /// What the prompt must print for a name: the same text with the characters `_mt_printable`
  /// replaces (controls, C1, zero-width and bidi) turned into `?`.
  static func visible(_ name: String) -> String {
    let replaced: [ClosedRange<UInt32>] = [
      0...0x1F, 0x7F...0x9F, 0x200B...0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF...0xFEFF,
    ]
    return String(String.UnicodeScalarView(name.unicodeScalars.map { scalar in
      replaced.contains { $0.contains(scalar.value) } ? "?" : scalar
    }))
  }

  private func assertInert(_ session: ZshSession) {
    #expect(!FileManager.default.fileExists(atPath: session.home.appending(path: "pwned").path))
    #expect(!FileManager.default.fileExists(atPath: session.home.appending(path: "repo/pwned").path))
    var text = session.text
    for own in [/\x1b\]7777;[0-9a-f]{32};[^\x07\x1b]*\x07/, /\x1b\]133;[A-D][^\x07\x1b]*\x07/, /\x1b\]7;file:\/\/[A-Za-z0-9._~\/%-]*\x07/] {
      text.replace(own, with: "")
    }
    #expect(!text.contains("\u{07}"), "BEL outside own marks")
    #expect(!text.contains("\u{1b}]"), "OSC outside own marks")
    #expect(!text.contains("\u{1b}[31m"), "prompt escape from data was interpreted")
    #expect(!text.unicodeScalars.contains("\u{202E}"), "bidi override reached the terminal")
    #expect(!text.contains("uid="), "command substitution ran")
  }
}

enum GitFixture {
  static func repository(at directory: URL, home: URL, branch: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    try run(["init", "-q", "-b", branch], in: directory, home: home)
    try run(
      ["-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "--allow-empty", "-m", "x"],
      in: directory, home: home)
    try Data("change".utf8).write(to: directory.appending(path: "untracked.txt"))
  }

  static func run(_ arguments: [String], in directory: URL, home: URL) throws {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1"]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CocoaError(.executableLoad, userInfo: ["git": arguments, "status": process.terminationStatus])
    }
  }
}
