import Testing

@testable import MacterminalCore

@Suite("ConfigParser")
struct ConfigParserTests {
  @Test func emptyTextGivesDefaultsWithoutIssues() {
    let (config, issues) = ConfigParser.parse("")
    #expect(config == .defaults)
    #expect(issues.isEmpty)
  }

  @Test func invalidValuesYieldIssuesWithLineNumbers() {
    let text = """
      font-size = 99
      intensity = loco
      foo = 1
      # comentario
      shell = /no/existe
      font-family = Menlo
      """
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.map(\.line) == [1, 2, 3, 5])
    #expect(issues.map(\.key) == ["font-size", "intensity", "foo", "shell"])
    #expect(config.fontSize == 13)
    #expect(config.intensity == .equilibrado)
    #expect(config.shell == TerminalConfig.defaults.shell)
    #expect(config.fontFamily == "Menlo")
  }

  @Test(arguments: [
    ("sutil", Intensity.sutil), ("equilibrado", .equilibrado), ("inmersivo", .inmersivo),
    ("subtle", .sutil), ("balanced", .equilibrado), ("immersive", .inmersivo),
  ])
  func intensityAcceptsSpanishValuesAndEnglishAliases(value: String, expected: Intensity) {
    let (config, issues) = ConfigParser.parse("intensity = \(value)")
    #expect(config.intensity == expected)
    #expect(issues.isEmpty)
  }

  @Test func englishIntensityAliasIsWrittenBackWithTheExistingValue() {
    let (config, _) = ConfigParser.parse("intensity = immersive")
    let written = ConfigWriter.setting(.intensity, to: config.intensity.rawValue, in: "")
    #expect(written.contains("intensity = inmersivo"))
    #expect(ConfigParser.parse(written).0.intensity == .inmersivo)
  }

  @Test(arguments: [
    ("font-size", "10", 10.0), ("font-size", "24", 24.0), ("font-size", "13,5", 13.5),
    ("font-size", "\"16\"", 16.0),
  ])
  func validFontSizes(key: String, value: String, expected: Double) {
    let (config, issues) = ConfigParser.parse("\(key)=\(value)")
    #expect(config.fontSize == expected)
    #expect(issues.isEmpty)
  }

  @Test(arguments: ["9.99", "24.01", "abc", "nan", "inf", "0x10", "", "-5", "1e1"])
  func invalidFontSizesFallBack(value: String) {
    let (config, issues) = ConfigParser.parse("font-size = \(value)")
    #expect(config.fontSize == 13)
    #expect(issues.count == 1)
  }

  @Test(arguments: [("0.5", 0.5), ("1", 1.0), ("0,75", 0.75)])
  func validOpacity(value: String, expected: Double) {
    let (config, issues) = ConfigParser.parse("background-opacity = \(value)")
    #expect(config.backgroundOpacity == expected)
    #expect(issues.isEmpty)
  }

  @Test(arguments: [("0", 0.5), ("0.49", 0.5), ("1.5", 1.0), ("-3", 0.5)])
  func outOfRangeOpacityIsClampedWithIssue(value: String, expected: Double) {
    let (config, issues) = ConfigParser.parse("background-opacity = \(value)")
    #expect(config.backgroundOpacity == expected)
    #expect(issues.count == 1)
  }

  @Test(.language("en")) func outOfRangeOpacityMessageShowsTheValueUsedWithoutTrailingZeros() {
    let (_, issues) = ConfigParser.parse("background-opacity = 3")
    #expect(issues.first?.message.hasSuffix("set to 1.") == true)
  }

  @Test func nonNumericOpacityFallsBackToDefault() {
    let (config, issues) = ConfigParser.parse("background-opacity = nan")
    #expect(config.backgroundOpacity == 1)
    #expect(issues.count == 1)
  }

  @Test func boolsIntensityHotkeyAndShell() {
    let text = """
      prompt = false
      autosuggest = false
      intensity = inmersivo
      quake-hotkey = cmd+shift+space
      shell = /bin/sh
      """
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.isEmpty)
    #expect(!config.prompt)
    #expect(!config.autosuggest)
    #expect(config.intensity == .inmersivo)
    #expect(config.quakeHotkey == KeyShortcut(configString: "cmd+shift+space"))
    #expect(config.shell == "/bin/sh")
  }

  @Test(arguments: ["yes", "1", "TRUE", ""])
  func invalidBoolFallsBackToDefault(value: String) {
    let (config, issues) = ConfigParser.parse("prompt = \(value)")
    #expect(config.prompt)
    #expect(issues.count == 1)
  }

  @Test func invalidHotkeyFallsBackToDefault() {
    let (config, issues) = ConfigParser.parse("quake-hotkey = ctrl+")
    #expect(config.quakeHotkey == KeyShortcut(configString: "ctrl+grave"))
    #expect(issues.count == 1)
  }

  @Test(arguments: ["/etc", "relativo", "/etc/hosts", ""])
  func nonExecutableShellFallsBack(value: String) {
    let (config, issues) = ConfigParser.parse("shell = \(value)")
    #expect(config.shell == TerminalConfig.defaults.shell)
    #expect(issues.count == 1)
  }

  @Test func quotesCommentsAndSpacing() {
    let text = "  # inicio\n\tfont-family   =   \"Fira Code\"  \nprompt=false\n"
    let (config, issues) = ConfigParser.parse(text)
    #expect(config.fontFamily == "Fira Code")
    #expect(!config.prompt)
    #expect(issues.isEmpty)
  }

  @Test func singleQuotesAndEqualsInsideValue() {
    let (config, issues) = ConfigParser.parse("font-family = 'A=B'")
    #expect(config.fontFamily == "A=B")
    #expect(issues.isEmpty)
  }

  @Test func lineWithoutEqualsIsReported() {
    let (config, issues) = ConfigParser.parse("hola\nprompt = false")
    #expect(issues.map(\.line) == [1])
    #expect(!config.prompt)
  }

  @Test func duplicateKeyWarnsAndLastWins() {
    let (config, issues) = ConfigParser.parse("font-size = 12\nfont-size = 15")
    #expect(config.fontSize == 15)
    #expect(issues.map(\.line) == [2])
  }

  @Test func duplicateWithInvalidLastFallsBackToDefault() {
    let (config, issues) = ConfigParser.parse("font-size = 12\nfont-size = 99")
    #expect(config.fontSize == 13)
    #expect(issues.map(\.line) == [2, 2])
  }

  @Test func emptyFontFamilyIsRejected() {
    let (config, issues) = ConfigParser.parse("font-family = \"\"")
    #expect(config.fontFamily == TerminalConfig.defaults.fontFamily)
    #expect(issues.count == 1)
  }

  @Test func crlfLinesAreParsed() {
    let (config, issues) = ConfigParser.parse("font-size = 14\r\nprompt = false\r\n")
    #expect(config.fontSize == 14)
    #expect(!config.prompt)
    #expect(issues.isEmpty)
  }

  @Test func oversizedTextIsRejected() {
    let text = "# " + String(repeating: "a", count: 100 * 1024) + "\nfont-size = 20"
    let (config, issues) = ConfigParser.parse(text)
    #expect(config == .defaults)
    #expect(issues.count == 1)
  }

  @Test func exactlyMaxSizeIsAccepted() {
    let filler = "#" + String(repeating: "a", count: ConfigParser.maxFileBytes - 1)
    let (_, issues) = ConfigParser.parse(filler)
    #expect(issues.isEmpty)
  }

  @Test func appliesTo() {
    #expect(ConfigKey.prompt.appliesTo == .newSessions)
    #expect(ConfigKey.autosuggest.appliesTo == .newSessions)
    #expect(ConfigKey.shell.appliesTo == .newSessions)
    #expect(ConfigKey.fontSize.appliesTo == .immediately)
    #expect(ConfigKey.quakeHotkey.appliesTo == .immediately)
  }
}
