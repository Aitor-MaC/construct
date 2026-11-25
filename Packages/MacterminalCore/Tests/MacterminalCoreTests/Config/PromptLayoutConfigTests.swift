import Testing

@testable import MacterminalCore

/// C4: `prompt-user-host` and `prompt-path` choose what the first prompt line shows.
@Suite struct PromptLayoutConfigTests {
  @Test func defaultsShowUserHostAndFullPath() {
    let (config, issues) = ConfigParser.parse("")
    #expect(issues.isEmpty)
    #expect(config.promptUserHost == .always)
    #expect(config.promptPath == .full)
  }

  @Test(arguments: PromptUserHost.allCases)
  func userHostValuesWrittenBySettingsAreReadBack(_ value: PromptUserHost) {
    let text = ConfigWriter.setting(.promptUserHost, to: value.rawValue, in: "")
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.isEmpty)
    #expect(config.promptUserHost == value)
  }

  @Test(arguments: PromptPath.allCases)
  func pathValuesWrittenBySettingsAreReadBack(_ value: PromptPath) {
    let text = ConfigWriter.setting(.promptPath, to: value.rawValue, in: "")
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.isEmpty)
    #expect(config.promptPath == value)
  }

  @Test(arguments: ["sometimes", "ALWAYS", "", "true"])
  func invalidUserHostFallsBackToDefaultWithIssue(_ value: String) {
    let (config, issues) = ConfigParser.parse("prompt-user-host = always\nprompt-user-host = \(value)")
    #expect(config.promptUserHost == .always)
    #expect(issues.last?.line == 2)
    #expect(issues.last?.key == "prompt-user-host")
  }

  @Test(arguments: ["long", "Full", "", "1"])
  func invalidPathFallsBackToDefaultWithIssue(_ value: String) {
    let (config, issues) = ConfigParser.parse("prompt-path = short\nprompt-path = \(value)")
    #expect(config.promptPath == .full)
    #expect(issues.last?.line == 2)
    #expect(issues.last?.key == "prompt-path")
  }

  @Test func bothKeysOnlyAffectNewSessions() {
    #expect(ConfigKey.promptUserHost.appliesTo == .newSessions)
    #expect(ConfigKey.promptPath.appliesTo == .newSessions)
  }
}
