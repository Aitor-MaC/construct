import Foundation

public enum TerminalAction: Sendable, Hashable {
  case newWindow, newTab, closePane, splitVertical, splitHorizontal
  case previousTab, nextTab
  case focusPane(Direction)
  case commandPalette, find, previousBlock, nextBlock, copyBlockCommand, copyBlockOutput
  case clearScreen
  case increaseFontSize, decreaseFontSize, resetFontSize
  case setIntensity(Intensity)
  case settings, reloadConfig, toggleQuake

  public static let catalog: [TerminalAction] = [
    .newWindow, .newTab, .closePane, .splitVertical, .splitHorizontal,
    .previousTab, .nextTab, .focusPane(.left), .focusPane(.right), .focusPane(.up),
    .focusPane(.down),
    .commandPalette, .find, .previousBlock, .nextBlock, .copyBlockCommand, .copyBlockOutput,
    .clearScreen,
    .increaseFontSize, .decreaseFontSize, .resetFontSize,
    .setIntensity(.sutil), .setIntensity(.equilibrado), .setIntensity(.inmersivo), .settings,
    .reloadConfig, .toggleQuake,
  ]
  public var title: String {
    switch self {
    case .newWindow:
      String(
        localized: "New Window", bundle: .localized, comment: "Menu item and command palette action.")
    case .newTab:
      String(
        localized: "New Tab", bundle: .localized, comment: "Menu item and command palette action.")
    case .closePane:
      String(
        localized: "Close Pane", bundle: .localized, comment: "Menu item and command palette action.")
    case .splitVertical:
      String(
        localized: "Split Vertically", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .splitHorizontal:
      String(
        localized: "Split Horizontally", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .previousTab:
      String(
        localized: "Previous Tab", bundle: .localized, comment: "Menu item and command palette action."
      )
    case .nextTab:
      String(
        localized: "Next Tab", bundle: .localized, comment: "Menu item and command palette action.")
    case .focusPane(.left):
      String(
        localized: "Focus Left Pane", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .focusPane(.right):
      String(
        localized: "Focus Right Pane", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .focusPane(.up):
      String(
        localized: "Focus Pane Above", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .focusPane(.down):
      String(
        localized: "Focus Pane Below", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .commandPalette:
      String(
        localized: "Command Palette", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .find:
      String(
        localized: "Find", bundle: .localized,
        comment: "Menu item and command palette action that opens the find bar.")
    case .previousBlock:
      String(
        localized: "Previous Block", bundle: .localized,
        comment: "Menu item and command palette action; a block is one command with its output.")
    case .nextBlock:
      String(
        localized: "Next Block", bundle: .localized,
        comment: "Menu item and command palette action; a block is one command with its output.")
    case .copyBlockCommand:
      String(
        localized: "Copy Block Command", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .copyBlockOutput:
      String(
        localized: "Copy Block Output", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .clearScreen:
      String(
        localized: "Clear Screen", bundle: .localized, comment: "Menu item and command palette action."
      )
    case .increaseFontSize:
      String(
        localized: "Increase Font Size", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .decreaseFontSize:
      String(
        localized: "Decrease Font Size", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .resetFontSize:
      String(
        localized: "Default Font Size", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .setIntensity(.sutil):
      String(
        localized: "Subtle Intensity", bundle: .localized,
        comment: "Menu item and command palette action for the Matrix rain intensity.")
    case .setIntensity(.equilibrado):
      String(
        localized: "Balanced Intensity", bundle: .localized,
        comment: "Menu item and command palette action for the Matrix rain intensity.")
    case .setIntensity(.inmersivo):
      String(
        localized: "Immersive Intensity", bundle: .localized,
        comment: "Menu item and command palette action for the Matrix rain intensity.")
    case .settings:
      String(
        localized: "Settings…", bundle: .localized,
        comment: "Menu item and command palette action that opens Settings.")
    case .reloadConfig:
      String(
        localized: "Reload Configuration", bundle: .localized,
        comment: "Menu item and command palette action.")
    case .toggleQuake:
      String(
        localized: "Show or Hide Quake Terminal", bundle: .localized,
        comment:
          "Menu item and command palette action; Quake is the drop-down terminal, keep the name.")
    }
  }
  public var shortcut: KeyShortcut? {
    let config: String
    switch self {
    case .newWindow: config = "cmd+n"
    case .newTab: config = "cmd+t"
    case .closePane: config = "cmd+w"
    case .splitVertical: config = "cmd+d"
    case .splitHorizontal: config = "cmd+shift+d"
    case .previousTab: config = "cmd+shift+["
    case .nextTab: config = "cmd+shift+]"
    case .focusPane(.left): config = "cmd+alt+left"
    case .focusPane(.right): config = "cmd+alt+right"
    case .focusPane(.up): config = "cmd+alt+up"
    case .focusPane(.down): config = "cmd+alt+down"
    case .commandPalette: config = "cmd+shift+p"
    case .find: config = "cmd+f"
    case .previousBlock: config = "cmd+up"
    case .nextBlock: config = "cmd+down"
    case .copyBlockCommand: config = "cmd+shift+c"
    case .copyBlockOutput: config = "cmd+alt+shift+c"
    case .clearScreen: config = "cmd+k"
    case .increaseFontSize: config = "cmd+plus"
    case .decreaseFontSize: config = "cmd+-"
    case .resetFontSize: config = "cmd+0"
    case .settings: config = "cmd+,"
    case .toggleQuake: config = "ctrl+grave"
    case .setIntensity, .reloadConfig: return nil
    }
    return KeyShortcut(configString: config)
  }
}
