import MacterminalCore
import SwiftUI

/// Teclado: atajo global de la terminal Quake.
struct KeyboardSettingsTab: View {
  let config: TerminalConfig
  let save: ConfigSave

  var body: some View {
    Form {
      Section {
        ShortcutRecorder(
          label: String(localized: "Show or hide the Quake terminal", comment: "Label of the global shortcut row in Settings > Keyboard. The Quake terminal is a window that slides down from the top of the screen, as in the game Quake."),
          shortcut: config.quakeHotkey
        ) { shortcut in
          save(.quakeHotkey, shortcut.configString)
        }
      } footer: {
        Text(
          String(
            localized: "Works from any app. The terminal slides down from the top edge of the screen."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: SettingsLayout.width, height: 220)
  }
}
