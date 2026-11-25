import MacterminalCore
import SwiftUI

/// Prompt: segmentos propios, qué muestra la primera línea y autosugerencias del historial.
struct PromptSettingsTab: View {
  let config: TerminalConfig
  let save: ConfigSave

  var body: some View {
    Form {
      Section {
        Toggle(isOn: flag(.prompt, config.prompt)) {
          Text(String(localized: "Construct prompt", comment: "Toggle title in Settings > Prompt for the custom shell prompt. Construct is the app name."))
          Text(String(localized: "Shows the current folder and git branch in Construct’s colors.", comment: "Description of the Construct prompt toggle in Settings > Prompt."))
        }
      } footer: {
        AppliesToNote(key: .prompt)
      }
      Section {
        Picker(selection: choice(.promptUserHost, config.promptUserHost)) {
          ForEach(PromptUserHost.allCases, id: \.self) { mode in
            Text(mode.settingsTitle).tag(mode)
          }
        } label: {
          Text(String(localized: "User and computer", comment: "Picker title in Settings > Prompt for when the prompt starts with the user name and the computer name (user@computer)."))
          Text(String(localized: "Starts the prompt with your user name and the computer’s name.", comment: "Description of the User and computer picker in Settings > Prompt."))
        }
        Picker(selection: choice(.promptPath, config.promptPath)) {
          ForEach(PromptPath.allCases, id: \.self) { style in
            Text(style.settingsTitle).tag(style)
          }
        } label: {
          Text(String(localized: "Folder", comment: "Picker title in Settings > Prompt for how the current folder path is shown. Noun."))
          Text(String(localized: "A long path is cut on the left with …/ so there’s always room to type.", comment: "Description of the Folder picker in Settings > Prompt. …/ is shown literally in the prompt; keep it."))
        }
      } footer: {
        AppliesToNote(key: .promptPath)
      }
      .disabled(!config.prompt)
      Section {
        Toggle(isOn: flag(.autosuggest, config.autosuggest)) {
          Text(String(localized: "Autosuggestions", comment: "Toggle title in Settings > Prompt for inline gray suggestions of the rest of the command."))
          Text(String(localized: "Suggests the rest of the command in gray based on your history. Accept it with →.", comment: "Description of the Autosuggestions toggle in Settings > Prompt."))
        }
      } footer: {
        AppliesToNote(key: .autosuggest)
      }
    }
    .formStyle(.grouped)
    .frame(width: SettingsLayout.width, height: 430)
  }

  private func flag(_ key: ConfigKey, _ value: Bool) -> Binding<Bool> {
    Binding(get: { value }, set: { save(key, $0 ? "true" : "false") })
  }

  /// Solo el setter escribe, es decir, solo cuando el usuario elige otra opción.
  private func choice<Value: RawRepresentable<String> & Hashable>(_ key: ConfigKey, _ value: Value) -> Binding<Value> {
    Binding(get: { value }, set: { save(key, $0.rawValue) })
  }
}

extension PromptUserHost {
  fileprivate var settingsTitle: String {
    switch self {
    case .always: String(localized: "Always", comment: "Option of the User and computer picker in Settings > Prompt.")
    case .ssh: String(localized: "Over SSH or as root", comment: "Option of the User and computer picker in Settings > Prompt: only shown in an SSH session or when the user is root. SSH and root are technical terms; keep them.")
    case .never: String(localized: "Never", comment: "Option of the User and computer picker in Settings > Prompt.")
    }
  }
}

extension PromptPath {
  fileprivate var settingsTitle: String {
    switch self {
    case .full: String(localized: "Full path", comment: "Option of the Folder picker in Settings > Prompt: the whole path, like ~/Projects/Construct.")
    case .short: String(localized: "Abbreviated (~/P/Construct)", comment: "Option of the Folder picker in Settings > Prompt: every folder but the last reduced to its first letter. Keep the example path as is.")
    }
  }
}
