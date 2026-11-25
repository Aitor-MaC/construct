import Testing

@testable import MacterminalCore

@Suite("ConfigWriter")
struct ConfigWriterTests {
  @Test func replacesExistingLineKeepingEverythingElse() {
    let text = "# mi config\nfoo = 1\nfont-size = 12\n\n# fin\n"
    let out = ConfigWriter.setting(.fontSize, to: "16", in: text)
    #expect(out == "# mi config\nfoo = 1\nfont-size = 16\n\n# fin\n")
  }

  @Test func appendsWhenMissing() {
    #expect(ConfigWriter.setting(.prompt, to: "false", in: "") == "prompt = false\n")
    #expect(
      ConfigWriter.setting(.prompt, to: "false", in: "# c\nfoo = 1\n")
        == "# c\nfoo = 1\nprompt = false\n")
    #expect(ConfigWriter.setting(.prompt, to: "false", in: "# c") == "# c\nprompt = false\n")
  }

  @Test func idempotent() {
    let once = ConfigWriter.setting(.fontSize, to: "16", in: "# c\nfont-size=12\n")
    let twice = ConfigWriter.setting(.fontSize, to: "16", in: once)
    #expect(once == twice)
    // Mismo valor con otra forma de escribirlo: no toca el texto.
    #expect(ConfigWriter.setting(.fontSize, to: "12", in: "font-size=12\n") == "font-size=12\n")
  }

  @Test func doesNotDuplicateKeys() {
    var text = ""
    for size in ["11", "12", "13"] { text = ConfigWriter.setting(.fontSize, to: size, in: text) }
    #expect(text == "font-size = 13\n")
  }

  @Test func commentedKeyIsNotReplaced() {
    let out = ConfigWriter.setting(.fontSize, to: "14", in: "# font-size = 12\n")
    #expect(out == "# font-size = 12\nfont-size = 14\n")
  }

  @Test func valuesWithSpacesAreQuoted() {
    let out = ConfigWriter.setting(.fontFamily, to: "Fira Code", in: "")
    #expect(out == "font-family = \"Fira Code\"\n")
    #expect(ConfigParser.parse(out).0.fontFamily == "Fira Code")
  }

  @Test func newlinesCannotInjectKeys() {
    let out = ConfigWriter.setting(.fontFamily, to: "A\nprompt = false", in: "")
    let (config, issues) = ConfigParser.parse(out)
    #expect(config.prompt)
    #expect(issues.isEmpty)
    #expect(out.split(separator: "\n").count == 1)
  }

  @Test func preservesCRLF() {
    let out = ConfigWriter.setting(.fontSize, to: "15", in: "a = 1\r\nfont-size = 12\r\n")
    #expect(out == "a = 1\r\nfont-size = 15\r\n")
  }

  @Test func loneCRLinesAreSeparatedLikeTheParser() {
    let text = "font-size = 12\rprompt = false\r"
    let out = ConfigWriter.setting(.fontSize, to: "14", in: text)
    #expect(out == "font-size = 14\rprompt = false\r")
    let appended = ConfigWriter.setting(.autosuggest, to: "false", in: text)
    #expect(appended == "font-size = 12\rprompt = false\rautosuggest = false\r")
    let (config, issues) = ConfigParser.parse(out)
    #expect(config.fontSize == 14 && !config.prompt && issues.isEmpty)
  }

  @Test(arguments: [
    (ConfigKey.fontFamily, "Fira Code"), (.fontSize, "18"), (.intensity, "inmersivo"),
    (.prompt, "false"), (.autosuggest, "false"), (.backgroundOpacity, "0.8"),
    (.quakeHotkey, "cmd+shift+space"), (.shell, "/bin/sh"), (.greetingName, "Thomas 'Neo' Anderson"),
  ])
  func roundTripThroughParser(key: ConfigKey, value: String) {
    let text = ConfigWriter.setting(key, to: value, in: "# cabecera\n")
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.isEmpty)
    #expect(config != .defaults)
  }
}
