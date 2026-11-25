import Testing

@testable import MacterminalCore

@Suite("KeyShortcut glifos", .language("en"))
struct KeyShortcutGlyphsTests {
  @Test(
    "modificadores en el orden de Apple y tecla en mayúscula",
    arguments: [
      ("cmd+shift+p", ["⇧", "⌘", "P"]),
      ("shift+cmd+ctrl+alt+k", ["⌃", "⌥", "⇧", "⌘", "K"]),
      ("cmd+alt+left", ["⌥", "⌘", "←"]),
      ("cmd+down", ["⌘", "↓"]),
      ("ctrl+grave", ["⌃", "`"]),
      ("cmd+,", ["⌘", ","]),
      ("cmd+return", ["⌘", "↩"]),
    ])
  func glyphs(config: String, expected: [String]) throws {
    let shortcut = try #require(KeyShortcut(configString: config))
    #expect(shortcut.glyphs == expected)
  }

  @Test func spokenDescriptionNamesEveryKey() throws {
    let palette = try #require(KeyShortcut(configString: "cmd+shift+p"))
    #expect(palette.spokenDescription == "Shift Command P")
    let left = try #require(KeyShortcut(configString: "cmd+alt+left"))
    #expect(left.spokenDescription == "Option Command Left Arrow")
  }
}
