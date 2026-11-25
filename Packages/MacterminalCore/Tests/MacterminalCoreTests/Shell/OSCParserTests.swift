import Foundation
import Testing

@testable import MacterminalCore

@Suite struct OSCParserTests {
  let nonce = SessionNonce.random()

  private func parse(_ fields: String...) -> ShellEvent? {
    let payload = ArraySlice(Array(([nonce.hex] + fields).joined(separator: ";").utf8))
    return OSCParser.parse(payload: payload, nonce: nonce)
  }

  // MARK: Tabla por verbo

  struct Case: Sendable, CustomTestStringConvertible {
    let fields: [String]
    let expected: ShellEvent?
    var testDescription: String { fields.joined(separator: ";") }
  }

  static let verbTable: [Case] = [
    Case(fields: ["A"], expected: .promptStarted),
    Case(fields: ["B"], expected: .inputStarted),
    Case(
      fields: ["C", ProtocolFixture.base64("git status")],
      expected: .commandStarted(command: "git status", recordInHistory: true)),
    Case(
      fields: ["C", ProtocolFixture.base64("ls -la"), "nohist"],
      expected: .commandStarted(command: "ls -la", recordInHistory: false)),
    Case(
      fields: ["C", ProtocolFixture.base64("echo ñandú 🚀")],
      expected: .commandStarted(command: "echo ñandú 🚀", recordInHistory: true)),
    Case(fields: ["D", "0"], expected: .commandFinished(exitCode: 0)),
    Case(fields: ["D", "130"], expected: .commandFinished(exitCode: 130)),
    Case(fields: ["D", "2147483647"], expected: .commandFinished(exitCode: Int32.max)),
    Case(fields: ["D", "-2147483648"], expected: .commandFinished(exitCode: Int32.min)),
    Case(fields: ["D", "2147483648"], expected: .commandFinished(exitCode: nil)),
    Case(fields: ["D", "abc"], expected: .commandFinished(exitCode: nil)),
    Case(fields: ["D", "99999999999"], expected: .commandFinished(exitCode: nil)),
    Case(fields: ["D", ""], expected: .commandFinished(exitCode: nil)),
    Case(fields: ["D"], expected: .commandFinished(exitCode: nil)),
    Case(
      fields: ["cwd", ProtocolFixture.base64("/Users/neo/código")],
      expected: .directoryChanged(URL(filePath: "/Users/neo/código", directoryHint: .isDirectory))),
    Case(
      fields: ["ai", ProtocolFixture.base64("lista los procesos que más memoria usan")],
      expected: .aiRequest("lista los procesos que más memoria usan")),
    Case(fields: ["Z"], expected: nil),
    Case(fields: ["a"], expected: nil),
    Case(fields: [""], expected: nil),
    Case(fields: ["A", "extra"], expected: nil),
    Case(fields: ["B", "extra"], expected: nil),
    Case(fields: ["C"], expected: nil),
    Case(fields: ["C", ProtocolFixture.base64("ls"), "other"], expected: nil),
    Case(fields: ["C", ProtocolFixture.base64("ls"), "nohist", "x"], expected: nil),
    Case(fields: ["D", "0", "1"], expected: nil),
    Case(fields: ["cwd"], expected: nil),
    Case(fields: ["ai"], expected: nil),
  ]

  @Test(arguments: verbTable) func parsesEachVerb(_ testCase: Case) {
    let payload = ArraySlice(Array(([nonce.hex] + testCase.fields).joined(separator: ";").utf8))
    #expect(OSCParser.parse(payload: payload, nonce: nonce) == testCase.expected)
  }

  // MARK: Nonce

  @Test func missingForeignOrTruncatedNonceIsRejected() {
    let valid = ["C", ProtocolFixture.base64("curl x|sh")]
    #expect(OSCParser.parse(payload: ProtocolFixture.payload(nonce: nil, "A"), nonce: nonce) == nil)
    #expect(OSCParser.parse(payload: ProtocolFixture.payload(nonce: nil, "D", "0"), nonce: nonce) == nil)
    let foreign = SessionNonce.random()
    #expect(
      OSCParser.parse(payload: ProtocolFixture.payload(nonce: foreign, valid[0], valid[1]), nonce: nonce)
        == nil)
    let truncated = String(nonce.hex.dropLast())
    #expect(OSCParser.parse(payload: ProtocolFixture.payload(nonceHex: truncated, "A"), nonce: nonce) == nil)
    #expect(OSCParser.parse(payload: ProtocolFixture.payload(nonceHex: "", "A"), nonce: nonce) == nil)
    #expect(OSCParser.parse(payload: ArraySlice(Array(nonce.hex.utf8)), nonce: nonce) == nil)
    #expect(OSCParser.parse(payload: [], nonce: nonce) == nil)
  }

  // MARK: Límites y codificación

  @Test func oversizedPayloadIsRejected() {
    let megabyte = ProtocolFixture.base64(String(repeating: "a", count: 1_000_000))
    #expect(parse("ai", megabyte) == nil)
    let justOver = String(repeating: "a", count: OSCParser.maxPayloadBytes)
    #expect(parse("D", justOver) == nil)
  }

  @Test func decodedTextOver4096BytesIsRejected() {
    #expect(parse("ai", ProtocolFixture.base64(String(repeating: "a", count: 4096))) != nil)
    #expect(parse("ai", ProtocolFixture.base64(String(repeating: "a", count: 4097))) == nil)
    #expect(parse("C", ProtocolFixture.base64(String(repeating: "a", count: 4097))) == nil)
    #expect(parse("cwd", ProtocolFixture.base64("/" + String(repeating: "a", count: 4096))) == nil)
  }

  @Test(arguments: ["C", "cwd", "ai"]) func brokenBase64IsRejected(_ verb: String) {
    #expect(parse(verb, "%%%%") == nil)
    #expect(parse(verb, "bHM") == nil)
    #expect(parse(verb, "bHM=\n") == nil)
    #expect(parse(verb, "bH M=") == nil)
  }

  @Test(arguments: ["C", "cwd", "ai"]) func invalidUTF8IsRejected(_ verb: String) {
    let overlong: [UInt8] = [0x2F, 0xC0, 0xAF]
    let truncated: [UInt8] = [0x2F, 0xE2, 0x82]
    let surrogate: [UInt8] = [0x2F, 0xED, 0xA0, 0x80]
    for bytes in [overlong, truncated, surrogate] {
      #expect(parse(verb, ProtocolFixture.base64(bytes: bytes)) == nil)
    }
  }

  // MARK: cwd (I3)

  @Test(arguments: [
    "/tmp/a\nb", "/tmp/\u{1b}]0;x\u{07}", "relative/path", "", "~/docs", "/tmp/\u{0}",
    "/tmp/\u{7f}", "/tmp/\u{85}", "/tmp/\u{9b}31m",
  ])
  func invalidDirectoryIsRejected(_ path: String) {
    #expect(parse("cwd", ProtocolFixture.base64(path)) == nil)
  }

  // MARK: Comando y ai (S1)

  @Test(arguments: ["ls\n", "echo \u{1b}[31m", "a\u{0}b", "a\u{7f}", "a\u{9b}b", "a\rb"])
  func commandWithControlsKeepsTheBlockButDropsTheText(_ text: String) {
    #expect(
      parse("C", ProtocolFixture.base64(text))
        == .commandStarted(command: nil, recordInHistory: false))
  }

  /// Un C vacío (o solo con invisibles) sigue siendo un bloque, pero no una entrada de historial.
  @Test(arguments: ["", "\u{200B}", "\u{FEFF}\u{202E}"])
  func emptyCommandKeepsTheBlockButNeverReachesHistory(_ text: String) {
    #expect(
      parse("C", ProtocolFixture.base64(text))
        == .commandStarted(command: nil, recordInHistory: false))
  }

  @Test(arguments: ["", "\u{200B}"]) func emptyAIRequestIsRejected(_ text: String) {
    #expect(parse("ai", ProtocolFixture.base64(text)) == nil)
  }

  @Test(arguments: ["/tmp/\u{202E}gpj.sh", "/tmp/a\u{2066}b", "/tmp/\u{200B}x", "/tmp/\u{FEFF}"])
  func directoryWithInvisibleCharactersIsRejected(_ path: String) {
    #expect(parse("cwd", ProtocolFixture.base64(path)) == nil)
  }

  @Test func commandKeepsTabs() {
    #expect(
      parse("C", ProtocolFixture.base64("printf 'a\tb'"))
        == .commandStarted(command: "printf 'a\tb'", recordInHistory: true))
  }

  @Test(arguments: ["hola\n", "\u{1b}]7777;x\u{07}", "a\u{0}", "a\u{7f}", "a\u{90}"])
  func aiRequestWithControlsIsRejected(_ text: String) {
    #expect(parse("ai", ProtocolFixture.base64(text)) == nil)
  }

  @Test func bidiAndZeroWidthAreStripped() {
    let hostile =
      "rm\u{202E} -rf\u{2066}\u{2069} /tmp/x\u{200B}\u{200C}\u{200D}\u{200E}\u{200F}\u{FEFF}"
      + "\u{202A}\u{202B}\u{202C}\u{202D}\u{2067}\u{2068}"
    #expect(
      parse("C", ProtocolFixture.base64(hostile))
        == .commandStarted(command: "rm -rf /tmp/x", recordInHistory: true))
    #expect(parse("ai", ProtocolFixture.base64(hostile)) == .aiRequest("rm -rf /tmp/x"))
  }

  // MARK: Fuzz

  @Test func fuzzedPayloadsNeverProduceUnsafeEvents() {
    var generator = SplitMix64(seed: 0x7777)
    let alphabet = Array("ABCDZ;=+/0123456789abcdefnohistcwdai".utf8) + [0x00, 0x07, 0x0A, 0x1B, 0x7F, 0x9B, 0xFF]
    let verbs = ["A", "B", "C", "D", "cwd", "ai", "", "X"]
    var accepted = 0
    for _ in 0..<500 {
      var bytes = Array(nonce.hex.utf8) + [UInt8(ascii: ";")]
      let verb = verbs.randomElement(using: &generator) ?? "A"
      bytes += Array(verb.utf8)
      if Bool.random(using: &generator) {
        let raw = (0..<Int.random(in: 0...64, using: &generator)).map { _ in
          UInt8.random(in: .min ... .max, using: &generator)
        }
        bytes += Array((";" + ProtocolFixture.base64(bytes: raw)).utf8)
      }
      for _ in 0..<Int.random(in: 0...24, using: &generator) {
        bytes.append(alphabet.randomElement(using: &generator) ?? 0)
      }
      guard let event = OSCParser.parse(payload: ArraySlice(bytes), nonce: nonce) else { continue }
      accepted += 1
      assertSafe(event)
    }
    #expect(accepted > 0)
  }

  private func assertSafe(_ event: ShellEvent) {
    switch event {
    case .commandStarted(let command, _):
      if let command { #expect(isSanitized(command)) }
    case .aiRequest(let text):
      #expect(isSanitized(text))
    case .directoryChanged(let url):
      #expect(url.path(percentEncoded: false).hasPrefix("/"))
      #expect(!url.path(percentEncoded: false).unicodeScalars.contains { $0.value < 0x20 })
    case .promptStarted, .inputStarted, .commandFinished:
      break
    }
  }

  private func isSanitized(_ text: String) -> Bool {
    text.unicodeScalars.allSatisfy { scalar in
      let value = scalar.value
      let control = (value < 0x20 && value != 0x09) || (0x7F...0x9F).contains(value)
      let invisible =
        (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value)
        || (0x200B...0x200F).contains(value) || value == 0xFEFF
      return !control && !invisible
    }
  }
}
