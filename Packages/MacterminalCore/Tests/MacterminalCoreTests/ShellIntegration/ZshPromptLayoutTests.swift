import Foundation
import Testing

@testable import MacterminalCore

/// C4: `user@host` segment and full path on the first prompt line, drawn by a real zsh.
@Suite struct ZshPromptLayoutTests {
  static let host = "HOST=MacBook-Pro.local"

  @Test func defaultShowsUserAtShortHostAndFullPath() async throws {
    let session = try ZshSession(zshrc: Self.host) { home in
      try FileManager.default.createDirectory(
        at: home.appending(path: "Proyectos Apps/Macterminal"), withIntermediateDirectories: true)
    }
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("cd ~/'Proyectos Apps'/Macterminal"))
    let line = try #require(session.firstPromptLine)
    #expect(line.hasPrefix(" \(NSUserName())@MacBook-Pro "), "\(line)")
    #expect(line.contains(" ~/Proyectos Apps/Macterminal "), "\(line)")
    #expect(!line.contains(".local"))
  }

  @Test func neverAndShortKeepOnlyTheAbbreviatedPath() async throws {
    let options = PromptOptions(prompt: true, autosuggest: true, userHost: .never, path: .short)
    let session = try ZshSession(options: options, zshrc: Self.host) { home in
      for path in ["Proyectos Apps/Macterminal", ".config/zsh"] {
        try FileManager.default.createDirectory(
          at: home.appending(path: path), withIntermediateDirectories: true)
      }
    }
    #expect(await session.waitForPrompt(1))
    #expect(session.firstPromptLine?.hasPrefix(" ~ ") == true, "\(session.firstPromptLine ?? "")")
    #expect(await session.run("cd ~/'Proyectos Apps'/Macterminal"))
    #expect(session.firstPromptLine?.hasPrefix(" ~/P/Macterminal ") == true)
    #expect(await session.run("cd ~/.config/zsh"))
    #expect(session.firstPromptLine?.hasPrefix(" ~/.c/zsh ") == true)
    #expect(!session.text.contains("@MacBook-Pro"))
  }

  @Test(arguments: [false, true])
  func sshModeShowsUserHostOnlyOverSSH(overSSH: Bool) async throws {
    let options = PromptOptions(prompt: true, autosuggest: true, userHost: .ssh, path: .full)
    let ssh = overSSH ? "\nexport SSH_CONNECTION='192.0.2.1 50000 192.0.2.2 22'" : ""
    let session = try ZshSession(options: options, zshrc: Self.host + ssh)
    #expect(await session.waitForPrompt(1))
    let line = try #require(session.firstPromptLine)
    if overSSH {
      #expect(line.hasPrefix(" ⇄ \(NSUserName())@MacBook-Pro "), "\(line)")
    } else {
      #expect(line.hasPrefix(" ~ "), "\(line)")
      #expect(!line.contains("@"))
    }
  }

  @Test func longPathIsCutOnTheLeftAndLeavesThirtyColumns() async throws {
    let deep = "client-projects/2026/matrix-terminal-for-macos/Packages/MacterminalCore/ShellIntegration"
    let session = try ZshSession(zshrc: Self.host, columns: 80) { home in
      try FileManager.default.createDirectory(
        at: home.appending(path: deep), withIntermediateDirectories: true)
    }
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("cd ~/\(deep)"))
    let line = try #require(session.firstPromptLine)
    #expect(line.contains(" …/"), "\(line)")
    #expect(line.contains("/ShellIntegration "), "\(line)")
    #expect(!line.contains("client-projects"))
    #expect(line.count <= 80 - 30, "\(line.count) columns: \(line)")
  }

  /// The leading `/` of an absolute path is the root, not a folder that can be dropped: `/` and
  /// `/usr` stay whole even when the budget is negative in a narrow pane.
  @Test(arguments: [40, 55])
  func rootAndShortAbsolutePathsAreNeverCut(columns: Int) async throws {
    let session = try ZshSession(zshrc: Self.host, columns: columns)
    #expect(await session.waitForPrompt(1))
    for path in ["/", "/usr"] {
      #expect(await session.run("cd \(path)"))
      let line = try #require(session.firstPromptLine)
      #expect(line.hasPrefix(" \(NSUserName())@MacBook-Pro "), "\(line)")
      #expect(line.contains(" \(path) "), "\(line)")
      #expect(!line.contains("…"), "\(line)")
    }
  }

  @Test func longAbsolutePathOutsideHomeIsCutOnTheLeft() async throws {
    let deep = "outside/client-projects/2026/matrix-terminal/Packages/ShellIntegration"
    var outside: URL?
    let session = try ZshSession(zshrc: Self.host, columns: 80) { home in
      let directory = home.deletingLastPathComponent().appending(path: deep)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      outside = directory
    }
    let directory = try #require(outside)
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("cd '\(directory.path)'"))
    let line = try #require(session.firstPromptLine)
    #expect(line.contains(" …/"), "\(line)")
    #expect(line.contains("/ShellIntegration "), "\(line)")
    #expect(!line.contains("/private"), "\(line)")
    #expect(line.count <= 80 - 30, "\(line.count) columns: \(line)")
  }

  /// The layout options travel like the nonce: read once by .zshenv, never inherited by children.
  @Test func layoutOptionsAreNotExportedToChildren() async throws {
    let options = PromptOptions(prompt: true, autosuggest: true, userHost: .ssh, path: .short)
    let session = try ZshSession(options: options)
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("env"))
    let output = try #require(session.lastCommandOutput)
    #expect(output.contains("TERM_PROGRAM=Construct"))
    #expect(!output.contains("MACTERMINAL_"), "\(output)")
  }
}

extension ZshSession {
  /// First line of the newest prompt as the user sees it: what zsh drew after the last `A`
  /// mark, without escape sequences and without the PROMPT_SP filler that precedes it.
  var firstPromptLine: String? {
    let text = self.text
    guard let mark = text.range(of: "\u{1b}]7777;\(nonce);A\u{07}", options: .backwards)
    else { return nil }
    // The terminal turns "\n" into "\r\n", a single Character in Swift.
    let drawn = text[mark.upperBound...].replacing("\r\n", with: "\n")
    guard let end = drawn.firstIndex(of: "\n") else { return nil }
    var line = String(drawn[..<end])
    line.replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/, with: "")
    line.replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/, with: "")
    return line.split(separator: "\r", omittingEmptySubsequences: false).last.map(String.init)
  }
}
