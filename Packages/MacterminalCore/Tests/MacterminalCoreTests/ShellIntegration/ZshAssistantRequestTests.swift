import Foundation
import Testing

@testable import MacterminalCore

/// Requests for the assistant typed at the prompt (`#…`, `# …`, `??…`) and the grey hint that
/// shows while one is typed, with a real zsh in a PTY.
@Suite(.serialized) struct ZshAssistantRequestTests {
  /// ^T prints what follows the typed text and how it is highlighted, so a test can see the hint.
  static let probe = """
    _probe() { zle -M "PD:[$POSTDISPLAY] RH:[${(j:,:)region_highlight}]" }
    zle -N _probe
    bindkey '^T' _probe
    """
  static let englishHint = "  ⏎ ask Apple Intelligence"

  /// The hint is resolved when the shell starts, so the language is pinned there; otherwise it
  /// would follow the machine or `-testLanguage`.
  static func englishSession(
    options: PromptOptions = PromptOptions(prompt: true, autosuggest: true), zshrc: String
  ) throws -> ZshSession {
    try Localization.$language.withValue("en") { try ZshSession(options: options, zshrc: zshrc) }
  }

  @Test(arguments: [
    "#install powershell", "# install powershell", "?? install powershell", "??install powershell",
    "   #   install powershell  ",
  ])
  func prefixedLineIsReportedNeverRunAndNotRemembered(line: String) async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    session.send(line + "\r")
    #expect(await session.waitUntil { $0.marks.contains { $0.hasPrefix("ai;") } })
    #expect(requests(session) == ["install powershell"])
    #expect(await session.run(#"print -rl -- "${(@v)history}""#))
    #expect(session.marks.filter { $0.hasPrefix("C;") }.count == 1)
    let history = try #require(session.lastCommandOutput)
    #expect(!history.contains("install powershell"), "\(history)")
  }

  /// With bang_hist on, zsh itself stops `#!…` (event not found) before it reaches preexec.
  @Test(arguments: ["#!/bin/bash", "echo # hola", "ls"])
  func ordinaryLinesRunAsAlways(line: String) async throws {
    let session = try ZshSession(zshrc: "unsetopt bang_hist")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run(line))
    #expect(commands(session) == [line])
    #expect(requests(session).isEmpty)
  }

  /// A buffer with several lines (here a literal newline inserted with ^V^J) is not a request.
  @Test func multiLineBufferRunsAsAlways() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("# first\u{16}\u{0A}print -r -- second-$((1 + 1))"))
    #expect(commands(session) == ["# first\nprint -r -- second-$((1 + 1))"])
    #expect(requests(session).isEmpty)
    #expect(session.text.contains("second-2"))
  }

  /// Continuation lines (heredoc, unclosed quotes) belong to the command being typed: a `#` or
  /// `??` there is text, never a request.
  @Test(arguments: [
    (typed: "cat <<EOF > out.txt\r#title\r?? x\rbody\rEOF", written: "#title\n?? x\nbody\n"),
    (typed: "print -r -- \"a\r#x\" > out.txt", written: "a\n#x\n"),
  ])
  func continuationLinesAreTextNotRequests(typed: String, written: String) async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run(typed))
    #expect(requests(session).isEmpty)
    let file = try String(contentsOf: session.home.appending(path: "out.txt"), encoding: .utf8)
    #expect(file == written)
  }

  /// Every key redraws the hint, so a long pasted request must not slow typing down. The best of
  /// several runs keeps the measure independent of the machine's load.
  @Test func hintOnAVeryLongRequestStaysFast() async throws {
    let timer = """
      zmodload zsh/datetime
      _time_hint() {
        local start best=1e9 elapsed
        BUFFER="#${(l:40000::a:)}  "; CURSOR=${#BUFFER}
        repeat 5; do
          start=$EPOCHREALTIME; _mt_show_ai_hint; _mt_suggest
          elapsed=$(( (EPOCHREALTIME - start) * 1000 )); (( elapsed < best )) && best=$elapsed
        done
        BUFFER=; zle -M "MS:[${best%%.*}]"
      }
      zle -N _time_hint
      bindkey '^T' _time_hint
      """
    let session = try Self.englishSession(zshrc: timer)
    #expect(await session.waitForPrompt(1))
    session.send("\u{14}")
    #expect(await session.waitUntil { $0.text.contains("MS:[") })
    let milliseconds = try #require(
      session.text.firstMatch(of: /MS:\[(\d+)\]/).flatMap { Int($0.1) })
    #expect(milliseconds < 20)
  }

  @Test(arguments: ["#", "# ", "??", "  ?? "])
  func emptyRequestSendsNothingAndShowsTheHint(line: String) async throws {
    let session = try Self.englishSession(zshrc: Self.probe)
    #expect(await session.waitForPrompt(1))
    session.send(line + "\r\u{14}")
    #expect(await session.waitUntil { $0.text.contains("PD:[\(Self.englishHint)]") })
    #expect(await session.run("print -r -- after"))
    #expect(commands(session) == ["print -r -- after"])
    #expect(requests(session).isEmpty)
  }

  @Test(arguments: [true, false])
  func hintAppearsInGreyWithThePrefixAndGoesWithIt(autosuggest: Bool) async throws {
    let session = try Self.englishSession(
      options: PromptOptions(prompt: true, autosuggest: autosuggest), zshrc: Self.probe)
    #expect(await session.waitForPrompt(1))
    session.send("#\u{14}")
    #expect(await session.waitUntil { $0.text.contains("PD:[\(Self.englishHint)] RH:[1 27 fg=8") })
    let shownAt = session.bytes.count
    session.send("\u{7f}\u{14}")
    #expect(await session.waitUntil { $0.text(since: shownAt).contains("PD:[] RH:[]") })
  }

  /// A history line starting with # would otherwise be suggested over the hint, and accepting
  /// the suggestion must never paste the hint into the request.
  @Test func autosuggestionNeitherHidesNorAcceptsTheHint() async throws {
    let session = try Self.englishSession(zshrc: Self.probe + "\nunsetopt bang_hist")
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("#!/bin/true"))
    let typedAt = session.bytes.count
    session.send("#\u{14}")
    #expect(await session.waitUntil { $0.text(since: typedAt).contains("PD:[\(Self.englishHint)]") })
    session.send("\u{06}tell me\r")
    #expect(await session.waitUntil { $0.marks.contains { $0.hasPrefix("ai;") } })
    #expect(requests(session) == ["tell me"])
  }

  @Test func hintFollowsTheLanguage() async throws {
    let session = try Localization.$language.withValue("es") {
      try ZshSession(options: PromptOptions(prompt: true, autosuggest: false), zshrc: Self.probe)
    }
    #expect(await session.waitForPrompt(1))
    session.send("??\u{14}")
    #expect(await session.waitUntil { $0.text.contains("PD:[  ⏎ preguntar a Apple Intelligence]") })
  }

  /// The hint arrives through the environment, so it is treated as untrusted text.
  @Test func hintFromTheEnvironmentIsSanitisedAndCapped() async throws {
    let hostile = "\u{1b}]0;pwned\u{07}" + String(repeating: "x", count: 100)
    let session = try ZshSession(
      zshrc: Self.probe, environmentOverrides: ["MACTERMINAL_AI_HINT": hostile])
    #expect(await session.waitForPrompt(1))
    let typedAt = session.bytes.count
    session.send("#\u{14}")
    let expected = "  ?]0;pwned?" + String(repeating: "x", count: 80 - 10)
    #expect(await session.waitUntil { $0.text(since: typedAt).contains("PD:[\(expected)]") })
    #expect(!session.text(since: typedAt).contains("\u{1b}]0;pwned"))
  }

  @Test func hintVariableNeverReachesChildren() async throws {
    let session = try ZshSession()
    #expect(await session.waitForPrompt(1))
    #expect(await session.run("env"))
    let output = try #require(session.lastCommandOutput)
    #expect(output.contains("TERM_PROGRAM=Construct"))
    #expect(!output.contains("MACTERMINAL_AI_HINT"))
    #expect(!output.contains("Apple Intelligence"))
  }

  /// Each line is typed as is; ^V inserts the next control character literally. `parsed` is what
  /// the app's parser makes of the reported request (`nil`: rejected, so no card).
  @Test(arguments: [
    (typed: "#$(touch pwned)", raw: "$(touch pwned)", parsed: "$(touch pwned)"),
    (typed: "?? `touch pwned`; rm -rf keep", raw: "`touch pwned`; rm -rf keep", parsed: "`touch pwned`; rm -rf keep"),
    (typed: "#a\u{16}\u{1b}[31mb", raw: "a\u{1b}[31mb", parsed: nil),
    (typed: "#a\u{16}\u{0D}touch pwned", raw: "a\u{0D}touch pwned", parsed: nil),
    (typed: "#a\u{2028}touch pwned", raw: "a\u{2028}touch pwned", parsed: "a\u{2028}touch pwned"),
    (typed: "#abc\u{202E}fed", raw: "abc\u{202E}fed", parsed: "abcfed"),
  ] as [(typed: String, raw: String, parsed: String?)])
  func hostileRequestIsReportedVerbatimAndNeverRun(typed: String, raw: String, parsed: String?)
    async throws
  {
    let session = try ZshSession { home in
      try Data("kept".utf8).write(to: home.appending(path: "keep"))
    }
    #expect(await session.waitForPrompt(1))
    session.send(typed + "\r")
    #expect(await session.waitUntil { $0.marks.contains { $0.hasPrefix("ai;") } })
    #expect(requests(session) == [raw])
    let mark = try #require(session.marks.first { $0.hasPrefix("ai;") })
    let payload = Array("\(session.nonce);\(mark)".utf8)
    let event = OSCParser.parse(payload: payload[...], nonce: session.sessionNonce)
    #expect(event == parsed.map { .aiRequest($0) })
    #expect(await session.run("true"))
    #expect(commands(session) == ["true"])
    #expect(!FileManager.default.fileExists(atPath: session.home.appending(path: "pwned").path))
    #expect(FileManager.default.fileExists(atPath: session.home.appending(path: "keep").path))
  }

  private func requests(_ session: ZshSession) -> [String?] {
    session.marks.filter { $0.hasPrefix("ai;") }.map { ZshSession.decodeBase64($0.dropFirst(3)) }
  }

  private func commands(_ session: ZshSession) -> [String?] {
    session.marks.filter { $0.hasPrefix("C;") }.map { ZshSession.decodeBase64($0.dropFirst(2)) }
  }
}

extension ZshSession {
  /// What the shell printed after byte `offset`.
  func text(since offset: Int) -> String {
    String(decoding: bytes[offset...], as: UTF8.self)
  }
}
