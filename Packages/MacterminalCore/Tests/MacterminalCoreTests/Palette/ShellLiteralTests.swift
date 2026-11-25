import Foundation
import Testing

@testable import MacterminalCore

@Suite("ShellLiteral")
struct ShellLiteralTests {
  @Test("cierra y reabre la comilla simple en cada apóstrofo", arguments: [
    ("/tmp", "'/tmp'"),
    ("/a b/c", "'/a b/c'"),
    ("/it's", "'/it'\\''s'"),
    ("''", "''\\'''\\'''"),
    ("/$(rm -rf ~)/`x`", "'/$(rm -rf ~)/`x`'"),
    ("/año/日本", "'/año/日本'"),
  ])
  func singleQuotes(raw: String, expected: String) {
    #expect(ShellLiteral.singleQuoted(raw) == expected)
  }

  @Test func changeDirectoryHasNoTrailingReturn() {
    let command = ShellLiteral.changeDirectory(to: URL(filePath: "/Users/neo/My Folder"))
    #expect(command == "cd '/Users/neo/My Folder'")
    #expect(!command.contains("\r") && !command.contains("\n"))
  }
}
