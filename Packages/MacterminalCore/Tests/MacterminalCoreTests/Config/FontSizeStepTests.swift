import Testing

@testable import MacterminalCore

@Suite struct FontSizeStepTests {
  @Test(arguments: [
    (FontSizeStep.Change.increase, 13.0, 14.0), (.increase, 13.5, 14), (.decrease, 13, 12),
    (.decrease, 13.5, 13), (.reset, 18, 13), (.increase, 23, 24), (.decrease, 11, 10),
  ])
  func stepsWholePointsInsideTheConfigRange(change: FontSizeStep.Change, from: Double, to: Double) {
    #expect(FontSizeStep.apply(change, to: from) == to)
  }

  @Test(arguments: [
    (FontSizeStep.Change.increase, 24.0), (.decrease, 10), (.reset, 13),
  ])
  func aChangeThatDoesNotMoveTheSizeIsNil(change: FontSizeStep.Change, from: Double) {
    #expect(FontSizeStep.apply(change, to: from) == nil)
  }

  @Test func theWrittenValueParsesBackToTheSameSize() throws {
    let size = try #require(FontSizeStep.apply(.increase, to: 13))
    let text = ConfigWriter.setting(.fontSize, to: FontSizeStep.configValue(size), in: "")
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.isEmpty)
    #expect(config.fontSize == 14)
  }

  @Test func zoomShortcutsAreInTheCatalogWithThePlusKey() {
    #expect(KeyShortcut(configString: "cmd+plus")?.key == "plus")
    #expect(TerminalAction.increaseFontSize.shortcut == KeyShortcut(configString: "cmd+plus"))
    #expect(TerminalAction.decreaseFontSize.shortcut == KeyShortcut(configString: "cmd+-"))
    #expect(TerminalAction.resetFontSize.shortcut == KeyShortcut(configString: "cmd+0"))
    #expect(TerminalAction.catalog.contains(.increaseFontSize))
    #expect(KeyShortcut(configString: "cmd+plus")?.glyphs == ["⌘", "+"])
  }
}
