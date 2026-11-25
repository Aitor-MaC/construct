import Foundation
import Testing

@testable import MacterminalCore

@Suite struct PromptInsertionTests {
  @Test(arguments: ["git log\t", "git log", "echo ñandú 🚀", ""])
  func acceptsPlainTextUnchanged(_ text: String) {
    #expect(PromptInsertion.validate(text) == .success(text))
  }

  @Test(arguments: ["ls\n", "ls\r", "\u{1b}[201~", "a\u{0}", "a\u{7f}", "a\u{85}", "a\u{9b}"])
  func rejectsControlCharacters(_ text: String) {
    #expect(PromptInsertion.validate(text) == .failure(.controlCharacter))
  }

  @Test(arguments: ["\u{202E}x", "a\u{202A}", "a\u{2066}", "a\u{2069}"])
  func rejectsBidiControls(_ text: String) {
    #expect(PromptInsertion.validate(text) == .failure(.bidiControl))
  }

  /// Invisibles o saltos Unicode: lo que el usuario revisa en el prompt sería distinto de lo que zsh ejecuta.
  @Test(arguments: [
    "a\u{200B}b", "rm\u{200D}x", "a\u{200E}", "\u{FEFF}ls", "a\u{2028}b", "a\u{2029}",
  ])
  func rejectsInvisibleCharactersAndUnicodeLineBreaks(_ text: String) {
    #expect(PromptInsertion.validate(text) == .failure(.invisibleCharacter))
  }

  @Test func rejectsTextOver4096Bytes() {
    let limit = String(repeating: "a", count: 4096)
    #expect(PromptInsertion.validate(limit) == .success(limit))
    #expect(PromptInsertion.validate(limit + "a") == .failure(.tooLong))
    #expect(PromptInsertion.validate(String(repeating: "ñ", count: 2049)) == .failure(.tooLong))
  }

  @Test(arguments: [
    InsertionRejection.controlCharacter, .bidiControl, .invisibleCharacter, .tooLong,
  ])
  func rejectionsExplainThemselves(_ rejection: InsertionRejection) {
    let message = rejection.errorDescription ?? ""
    #expect(!message.isEmpty)
    #expect(message.contains("prompt"))
  }
}
