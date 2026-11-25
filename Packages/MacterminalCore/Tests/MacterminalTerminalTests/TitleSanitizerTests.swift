import Testing

@testable import MacterminalTerminal

@Suite struct TitleSanitizerTests {
  @Test(arguments: [
    ("vim main.swift", "vim main.swift"),
    (";touch pwned\n", ";touch pwned"),
    ("a\u{1b}[31mb", "a[31mb"),
    ("tab\there", "tabhere"),
    ("c1\u{9b}31m", "c131m"),
    ("del\u{7f}x", "delx"),
    ("bidi\u{202e}txt.exe", "biditxt.exe"),
    ("zero\u{200b}width\u{feff}", "zerowidth"),
    ("line\u{2028}sep\u{2029}", "linesep"),
    ("  espacios  ", "espacios"),
    ("ñ 日本 🍣", "ñ 日本 🍣"),
  ])
  func removesEverythingThatIsNotVisibleText(raw: String, expected: String) {
    #expect(TitleSanitizer.clean(raw) == expected)
  }

  @Test func capsAtEightyCharactersWithoutSplittingGraphemes() {
    let flags = String(repeating: "🇪🇸", count: 100)
    let cleaned = TitleSanitizer.clean(flags)
    #expect(cleaned.count == TitleSanitizer.maxCharacters)
    #expect(cleaned == String(repeating: "🇪🇸", count: 80))
  }

  @Test func controlOnlyTitleBecomesEmpty() {
    #expect(TitleSanitizer.clean("\n\r\u{07}\u{1b}") == "")
  }
}
