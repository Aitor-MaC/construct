import Foundation
import Testing

@testable import MacterminalCore

@Suite("SettingsInput")
struct SettingsInputTests {
  // MARK: - KeyShortcut.configString

  @Test func defaultQuakeHotkeySerializesAsConfigString() throws {
    let shortcut = try #require(KeyShortcut(configString: "ctrl+grave"))
    #expect(shortcut.configString == "ctrl+grave")
  }

  @Test func modifiersSerializeInStableOrder() throws {
    let shortcut = try #require(KeyShortcut(configString: "shift+cmd+alt+ctrl+space"))
    #expect(shortcut.configString == "ctrl+alt+shift+cmd+space")
  }

  @Test func everyCatalogShortcutRoundTripsThroughTheParser() throws {
    for shortcut in TerminalAction.catalog.compactMap(\.shortcut) {
      let parsed = try #require(KeyShortcut(configString: shortcut.configString))
      #expect(parsed == shortcut)
    }
  }

  @Test func serializedHotkeyIsReadBackByTheConfigFile() throws {
    let shortcut = try #require(KeyShortcut(configString: "alt+cmd+up"))
    let text = ConfigWriter.setting(.quakeHotkey, to: shortcut.configString, in: "")
    let (config, issues) = ConfigParser.parse(text)
    #expect(issues.isEmpty)
    #expect(config.quakeHotkey == shortcut)
  }

  // MARK: - Atajo Quake

  @Test(arguments: ["ctrl+grave", "alt+space", "ctrl+alt+t", "cmd+shift+9"])
  func acceptsShortcutsWithModifierAndNoConflict(_ text: String) throws {
    let shortcut = try #require(KeyShortcut(configString: text))
    #expect(SettingsInput.checkQuakeHotkey(shortcut) == .valid)
  }

  @Test(arguments: ["grave", "a", "shift+a", "shift+space"])
  func rejectsShortcutsWithoutARealModifier(_ text: String) throws {
    let shortcut = try #require(KeyShortcut(configString: text))
    #expect(SettingsInput.checkQuakeHotkey(shortcut) == .missingModifier)
  }

  @Test func reportsTheActionThatAlreadyUsesTheShortcut() throws {
    let newTab = try #require(KeyShortcut(configString: "cmd+t"))
    #expect(SettingsInput.checkQuakeHotkey(newTab) == .conflict(.newTab))
    let focusLeft = try #require(KeyShortcut(configString: "alt+cmd+left"))
    #expect(SettingsInput.checkQuakeHotkey(focusLeft) == .conflict(.focusPane(.left)))
  }

  // MARK: - Ruta del shell

  @Test func emptyShellPathMeansTheEnvironmentShell() throws {
    let folder = try TemporaryFolder()
    let shell = try folder.file("zsh", permissions: 0o755)
    #expect(SettingsInput.checkShellPath("", defaultShell: shell) == .valid(shell))
    #expect(SettingsInput.checkShellPath("   ", defaultShell: shell) == .valid(shell))
  }

  @Test func executableShellPathIsAcceptedTrimmed() throws {
    let folder = try TemporaryFolder()
    let shell = try folder.file("fish", permissions: 0o755)
    #expect(SettingsInput.checkShellPath(" \(shell)\n", defaultShell: "/bin/zsh") == .valid(shell))
  }

  @Test func nonExecutableShellPathsAreRejected() throws {
    let folder = try TemporaryFolder()
    let plain = try folder.file("notes", permissions: 0o644)
    for typed in [plain, folder.url.path, "zsh", folder.url.appending(path: "missing").path] {
      #expect(SettingsInput.checkShellPath(typed, defaultShell: "/bin/zsh") == .notExecutable)
    }
  }
}

/// Carpeta temporal exclusiva que se borra al liberarse.
private final class TemporaryFolder {
  let url: URL
  init() throws {
    url = FileManager.default.temporaryDirectory.appending(path: "settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: url) }
  func file(_ name: String, permissions: Int) throws -> String {
    let path = url.appending(path: name).path
    #expect(FileManager.default.createFile(atPath: path, contents: Data("#!/bin/sh\n".utf8)))
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
    return path
  }
}
