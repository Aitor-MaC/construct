import Testing

@testable import MacterminalTerminal

/// SwiftTerm 1.99.3 rechaza un pegado con `ESC [201~` y lo reintenta con `allowUnsafe: true`:
/// el fin de pegado llegaría al shell y lo que sigue se ejecutaría como tecleado.
@Suite struct PasteSanitizerTests {
  @Test(arguments: [
    ("ls -la", "ls -la"),
    ("echo\u{1b}[201~; rm -rf ~", "echo; rm -rf ~"),
    ("a\u{1b}[20\u{1b}[201~1~b", "ab"),
    ("multi\nlínea ñ", "multi\nlínea ñ"),
    ("\u{1b}[200~dentro\u{1b}[201~", "\u{1b}[200~dentro"),
  ])
  func removesEveryBracketedPasteEnd(pasted: String, expected: String) {
    #expect(PasteSanitizer.clean(pasted) == expected)
  }
}
