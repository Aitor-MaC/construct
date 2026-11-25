import Foundation
import Testing

@testable import MacterminalCore

@Suite("greeting-name en la configuración")
struct GreetingNameConfigTests {
  @Test func keyAppliesImmediately() {
    #expect(ConfigKey.greetingName.rawValue == "greeting-name")
    #expect(ConfigKey.greetingName.appliesTo == .immediately)
  }

  @Test func writtenNameParsesBack() {
    let text = ConfigWriter.setting(.greetingName, to: "Thomas Anderson", in: "")
    let (config, issues) = ConfigParser.parse(text)
    #expect(config.greetingName == "Thomas Anderson")
    #expect(issues.isEmpty)
  }

  @Test func nameIsSanitizedWhenParsed() {
    let (config, issues) = ConfigParser.parse("greeting-name = Ne\u{202E}o\n")
    #expect(config.greetingName == "Neo")
    #expect(issues.isEmpty)
  }

  @Test func emptyAfterSanitizingEqualsMissing() {
    let (config, issues) = ConfigParser.parse("greeting-name = \u{200B}\n")
    #expect(config.greetingName == nil)
    #expect(config == .defaults)
    #expect(issues.isEmpty)
  }

  @Test func removingDeletesEveryAssignmentAndKeepsTheRest() {
    var text = ConfigWriter.setting(.greetingName, to: "Neo", in: "# mi config\nfont-size = 14\n")
    text += "greeting-name = Trinity\n# fin\n"
    #expect(
      ConfigWriter.removing(.greetingName, in: text) == "# mi config\nfont-size = 14\n# fin\n")
  }

  @Test func removingAMissingKeyLeavesTextUntouched() {
    let text = "# greeting-name = Neo\nfont-size = 14"
    #expect(ConfigWriter.removing(.greetingName, in: text) == text)
  }
}

@MainActor
@Suite("ConfigStore.remove")
struct ConfigStoreRemoveTests {
  @Test func removeDeletesKeyAndReloads() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    let store = ConfigStore(fileURL: file)
    try store.set(.fontSize, "14")
    try store.set(.greetingName, "Neo")
    #expect(store.config.greetingName == "Neo")
    try store.remove(.greetingName)
    #expect(store.config.greetingName == nil)
    #expect(try String(contentsOf: file, encoding: .utf8) == "font-size = 14\n")
  }

  @Test func removeWithoutFileDoesNotCreateIt() throws {
    let dir = try TempDir()
    defer { dir.remove() }
    let file = dir.url.appending(path: "config")
    let store = ConfigStore(fileURL: file)
    try store.remove(.greetingName)
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }
}
