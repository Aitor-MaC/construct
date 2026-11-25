import Foundation
import Testing

@testable import MacterminalCore

@Suite struct ZshSessionTests {
  @Test func commandProducesMarksInOrderAndHidesNonce() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("env; print -r -- \"HF=$HISTFILE\""))
    let marks = session.marks
    let verbs = marks.map { $0.hasPrefix("D;") ? $0 : String($0.prefix { $0 != ";" }) }
    #expect(verbs == ["cwd", "A", "B", "C", "D;0", "cwd", "A", "B"], "\(marks)")
    let cwd = try #require(marks.first { $0.hasPrefix("cwd;") })
    #expect(ZshSession.decodeBase64(cwd.dropFirst(4)) == session.home.path)
    let output = try #require(session.lastCommandOutput)
    #expect(output.contains("TERM_PROGRAM=Construct"))
    #expect(!output.contains(session.nonce))
    #expect(!session.text.contains("MACTERMINAL_NONCE"))
    #expect(!session.text.contains("MACTERMINAL_USER_ZDOTDIR"))
    #expect(session.text.contains("TERM_PROGRAM=Construct"))
    #expect(session.text.contains("HF=\(session.home.path)/.zsh_history"))
    #expect(session.text.contains("\u{1b}]133;A\u{07}"))
    #expect(session.text.contains("\u{1b}]133;B\u{07}"))
    #expect(session.text.contains("\u{1b}]133;C\u{07}"))
    #expect(session.text.contains("\u{1b}]133;D;0\u{07}"))
  }

  /// The input mark carries the nonce inside the prompt; a prompt the user exported (common in
  /// rc files copied from bash) must not hand it to every child process.
  @Test(arguments: [true, false])
  func exportedUserPromptNeverLeaksNonceToChildren(prompt: Bool) async throws {
    let session = try ZshSession(
      options: PromptOptions(prompt: prompt, autosuggest: false),
      zshrc: "export PS1='mine%# '\nexport PROMPT=$PS1")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("env"))
    let output = try #require(session.lastCommandOutput)
    #expect(output.contains("TERM_PROGRAM=Construct"))
    #expect(!output.contains(session.nonce), "\(output)")
  }

  @Test func failingCommandReportsStatusAndShowsErrorSegment() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("(exit 3)"))
    #expect(session.marks.contains("D;3"))
    #expect(session.text.contains("✗ 3"))
  }

  @Test func ohMyZshStylePromptSubstConfigurationStillWorks() async throws {
    let zshrc = """
      setopt prompt_subst
      autoload -Uz add-zsh-hook
      omz_title() { : }
      add-zsh-hook precmd omz_title
      PROMPT='%n $(print -n omz)> '
      """
    for options in [PromptOptions(prompt: true, autosuggest: true), PromptOptions(prompt: false, autosuggest: false)] {
      let session = try ZshSession(options: options, zshrc: zshrc)
      #expect(await session.waitForPrompt(1))
      #expect(await session.run("print -r -- ran-$((40 + 2))"))
      #expect(session.text.contains("ran-42"))
      #expect(session.marks.contains("D;0"))
      #expect(session.text.contains("omz>") == !options.prompt)
      #expect(!session.text.contains("command not found"))
    }
  }

  @Test func nounsetAndCustomZdotdirStartWithoutErrors() async throws {
    let session = try ZshSession(
      zshrc: "setopt nounset\nexport RC_LOADED=yes", zshenv: "setopt nounset\nexport ENV_LOADED=yes",
      userZdotdir: ".config/zsh")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("print -r -- \"env=$ENV_LOADED rc=$RC_LOADED zd=$ZDOTDIR\""))
    #expect(session.text.contains("env=yes rc=yes zd=\(session.home.path)/.config/zsh"))
    #expect(session.marks.contains("D;0"))
    #expect(!session.text.contains("parameter not set"))
  }

  @Test func userPromptIsKeptWhenPromptIsDisabled() async throws {
    let session = try ZshSession(
      options: PromptOptions(prompt: false, autosuggest: false), zshrc: "PS1='mine%# '")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(session.text.contains("mine%"))
    #expect(!session.text.contains("❯"))
  }

  @Test func commandTextTravelsIntact() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    let command = #"print -rn -- 'a\b' -n '50%' ñandú 日本 > /dev/null"#
    #expect(await session.run(command))
    let mark = try #require(session.marks.first { $0.hasPrefix("C;") })
    #expect(ZshSession.decodeBase64(mark.dropFirst(2)) == command)
    #expect(!mark.hasSuffix(";nohist"))
  }

  @Test func privateCommandsAreMarkedNohist() async throws {
    let session = try ZshSession(zshrc: "HISTORY_IGNORE='(pwd|secret *)'")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run(" echo spaced"))
    #expect(await session.run("pwd"))
    #expect(await session.run("echo kept"))
    let commands = session.marks.filter { $0.hasPrefix("C;") }
    #expect(commands.count == 3)
    #expect(commands.map { $0.hasSuffix(";nohist") } == [true, true, false])
  }

  @Test func assistantRequestIsReportedAndNeverRun() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    session.send("# hola; touch pwned\r")
    let reported = await session.waitUntil { $0.marks.contains { $0.hasPrefix("ai;") } }
    #expect(reported)
    let mark = try #require(session.marks.first { $0.hasPrefix("ai;") })
    #expect(ZshSession.decodeBase64(mark.dropFirst(3)) == "hola; touch pwned")
    #expect(await session.run("print -r -- after"))
    #expect(session.marks.filter { $0.hasPrefix("C;") }.count == 1)
    #expect(!FileManager.default.fileExists(atPath: session.home.appending(path: "pwned").path))
  }

  /// ⌘K vacía los bloques y manda Ctrl-L; `clear-screen` no pasa por precmd, así que sin un A
  /// nuevo el panel se quedaría sin prompt activo hasta el siguiente comando.
  @Test func clearScreenAnnouncesTheRedrawnPromptAndKeepsTheTypedLine() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    session.send("print -r -- tras\u{0C}")
    let rearmed = await session.waitUntil { $0.marks.filter { $0 == "A" }.count >= 2 }
    #expect(rearmed)
    #expect(await session.waitForPrompt(2))
    #expect(await session.run(""))
    let commands = session.marks.filter { $0.hasPrefix("C;") }
    #expect(commands.count == 1)
    #expect(commands.first.flatMap { ZshSession.decodeBase64($0.dropFirst(2)) } == "print -r -- tras")
    #expect(!session.marks.prefix { !$0.hasPrefix("C;") }.contains { $0.hasPrefix("D;") })
  }

  @Test func longCommandShowsDurationAndWideTerminalShowsTime() async throws {
    let session = try ZshSession(columns: 120)
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(session.text.firstMatch(of: /\d,\d s/) == nil)
    #expect(await session.run("sleep 2.1"))
    #expect(session.text.firstMatch(of: /2,[1-9] s/) != nil)
    #expect(session.text.firstMatch(of: /\d\d:\d\d:\d\d/) != nil)
  }

  @Test func narrowTerminalHidesTime() async throws {
    let session = try ZshSession(columns: 70)
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("true"))
    #expect(session.text.firstMatch(of: /\d\d:\d\d:\d\d/) == nil)
  }

  /// Real bytes for T7's script → parser → BlockTracker tests. Rewritten only when
  /// MACTERMINAL_RECORD_FIXTURES=1, so normal runs never touch the source tree.
  @Test func referenceSessionCoversEveryVerb() async throws {
    let session = try ZshSession(zshrc: "HOST=fixture-host")
    #expect(await session.waitForPrompt(1))
    for command in ["echo hola", "(exit 3)", " echo oculto", "print -r -- 'ñ 日本 %'"] {
      #expect(await session.run(command))
    }
    session.send("# explica esto\r")
    #expect(await session.waitUntil { $0.marks.contains { $0.hasPrefix("ai;") } })
    let verbs = Set(session.marks.map { String($0.prefix { $0 != ";" }) })
    #expect(verbs == ["A", "B", "C", "D", "cwd", "ai"])
    guard ProcessInfo.processInfo.environment["MACTERMINAL_RECORD_FIXTURES"] == "1" else { return }
    let fixtures = URL(filePath: #filePath).deletingLastPathComponent()
      .appending(path: "../../Fixtures/ShellIntegration").standardized
    try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
    try Data(session.bytes).write(to: fixtures.appending(path: "zsh-session.bin"))
    try Data(session.nonce.utf8).write(to: fixtures.appending(path: "zsh-session.nonce"))
  }

  @Test func directoryUrlIsPercentEncoded() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    let directory = session.home.appending(path: "dir ñ#?%")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    #expect(await session.run("cd 'dir ñ#?%'"))
    let urls = session.text.matches(of: /\x1b\]7;file:\/\/([^\x07]*)\x07/).map { String($0.output.1) }
    let last = try #require(urls.last)
    let path = String(last.drop { $0 != "/" })
    #expect(path.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~/%".contains($0)) })
    #expect(path.removingPercentEncoding == directory.path)
  }
}
