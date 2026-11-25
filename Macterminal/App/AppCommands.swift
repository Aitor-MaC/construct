import MacterminalCore
import SwiftUI

struct AppCommands: Commands {
  @Bindable var registry: ActionRegistry
  let settingsOpener: SettingsOpener
  @Environment(\.openSettings) private var openSettings
  var body: some Commands {
    // `Commands` no tiene `onAppear`: el cuerpo se evalúa al arrancar, antes de cualquier uso del
    // menú o de la paleta, y reasignar la misma acción es inocuo.
    let _ = settingsOpener.action = openSettings
    CommandMenu(String(localized: "Terminal", comment: "Title of the Terminal menu in the menu bar.")) {
      ForEach(TerminalAction.catalog, id: \.self) { action in
        actionButton(action)
      }
    }
  }
  private func actionButton(_ action: TerminalAction) -> some View {
    Button(action.title) { registry.perform(action) }
      .disabled(!registry.canPerform(action, in: registry.context))
      .keyboardShortcut(
        action.shortcut.map { KeyboardShortcut(keyEquivalent($0.key), modifiers: modifiers($0)) })
  }
  private func modifiers(_ shortcut: KeyShortcut) -> EventModifiers {
    var result: EventModifiers = []
    if shortcut.modifiers.contains(.cmd) { result.insert(.command) }
    if shortcut.modifiers.contains(.ctrl) { result.insert(.control) }
    if shortcut.modifiers.contains(.alt) { result.insert(.option) }
    if shortcut.modifiers.contains(.shift) { result.insert(.shift) }
    return result
  }
  private func keyEquivalent(_ key: String) -> KeyEquivalent {
    switch key {
    case "left": .leftArrow
    case "right": .rightArrow
    case "up": .upArrow
    case "down": .downArrow
    case "grave": "`"
    case "plus": "+"
    default: KeyEquivalent(key.first ?? " ")
    }
  }
}
