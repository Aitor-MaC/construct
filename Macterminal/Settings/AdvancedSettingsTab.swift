import AppKit
import MacterminalCore
import SwiftUI
import UniformTypeIdentifiers

/// Avanzado: ruta del shell, archivo de configuración y avisos del parser.
struct AdvancedSettingsTab: View {
  let store: ConfigStore
  let configFileURL: URL?
  let save: ConfigSave
  let onError: (String) -> Void

  @State private var shellDraft = ""
  @State private var shellRejected = false
  @State private var fileExists = false
  @FocusState private var shellFocused: Bool

  var body: some View {
    Form {
      shellSection
      fileSection
      issuesSection
    }
    .formStyle(.grouped)
    .frame(width: SettingsLayout.width, height: 500)
    .onAppear {
      shellDraft = store.config.shell
      refreshFileExists()
    }
    .onChange(of: store.config.shell) { _, shell in
      guard !shellFocused else { return }
      shellDraft = shell
      shellRejected = false
    }
    .onChange(of: store.issues) { refreshFileExists() }
  }

  // MARK: - Shell

  private var shellSection: some View {
    Section {
      TextField(
        String(localized: "Shell path", comment: "Label of the text field in Settings > Advanced for the executable path of the shell."), text: $shellDraft,
        prompt: Text(TerminalConfig.defaults.shell)
      )
      .focused($shellFocused)
      .onSubmit(commitShell)
      .onChange(of: shellFocused) { _, focused in if !focused { commitShell() } }
      .onChange(of: shellDraft) { shellRejected = false }
      .accessibilityHint(String(localized: "Leave empty to use your login shell.", comment: "Hint under the shell path field in Settings > Advanced."))
      if shellRejected {
        Label(
          String(localized: "That path isn’t an executable program. Enter a full path, such as /bin/zsh.", comment: "Error under the shell path field in Settings > Advanced."),
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.red)
      }
    } header: {
      Text(String(localized: "Shell", comment: "Section title in Settings > Advanced for the command interpreter (zsh). Noun, not the Unix term translated literally if a standard one exists."))
    } footer: {
      AppliesToNote(key: .shell)
    }
  }

  private func commitShell() {
    switch SettingsInput.checkShellPath(shellDraft) {
    case .notExecutable:
      shellRejected = true
    case .valid(let path):
      shellRejected = false
      guard path != store.config.shell else { return }
      if !save(.shell, path) { shellDraft = store.config.shell }
    }
  }

  // MARK: - Archivo

  private var fileSection: some View {
    Section(String(localized: "Configuration File", comment: "Section title in Settings > Advanced for the text file that stores the settings.")) {
      if let configFileURL {
        LabeledContent(String(localized: "Location", comment: "Row label in Settings > Advanced for the path of the configuration file.")) {
          Text(verbatim: (configFileURL.path as NSString).abbreviatingWithTildeInPath)
            .monospaced()
            .textSelection(.enabled)
        }
        HStack {
          Button(
            fileExists ? String(localized: "Open in Editor", comment: "Button in Settings > Advanced that opens the configuration file in a text editor.") : String(localized: "Create File", comment: "Button in Settings > Advanced that creates the configuration file when it doesn't exist yet.")
          ) { openFile(configFileURL) }
          Button(String(localized: "Reload", comment: "Button in Settings > Advanced that reads the configuration file again. Verb.")) { store.reload() }
            .keyboardShortcut("r", modifiers: .command)
            .help(String(localized: "Reads the file again (⌘R)", comment: "Tooltip of the Reload button in Settings > Advanced; ⌘R is Command+R."))
        }
      } else {
        Text(String(localized: "The file location isn’t available.", comment: "Error toast when the path of the configuration file can't be determined."))
          .foregroundStyle(.secondary)
      }
    }
  }

  private func openFile(_ url: URL) {
    // Crear = escribir el valor actual: el archivo nace por la misma vía que cualquier ajuste.
    if !fileExists, !save(.intensity, store.config.intensity.rawValue) { return }
    refreshFileExists()
    guard let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else {
      onError(String(localized: "There’s no app to edit text. Open the file from Finder.", comment: "Error toast when no application can open the configuration file."))
      return
    }
    NSWorkspace.shared.open(
      [url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration()
    ) { _, error in
      guard error != nil else { return }
      Task { @MainActor in
        onError(String(localized: "The file couldn’t be opened. Open it from Finder.", comment: "Error toast when the configuration file can't be opened in an editor."))
      }
    }
  }

  private func refreshFileExists() {
    fileExists = configFileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
  }

  // MARK: - Avisos

  private var issuesSection: some View {
    Section(String(localized: "File Warnings", comment: "Section title in Settings > Advanced listing problems found in the configuration file.")) {
      if store.issues.isEmpty {
        Label(String(localized: "No warnings: every line was read correctly.", comment: "Message in Settings > Advanced when the configuration file has no problems."), systemImage: "checkmark.circle")
          .foregroundStyle(.secondary)
      } else {
        // La lista se sustituye entera en cada recarga y nunca se anima: el índice basta como id.
        ForEach(Array(store.issues.enumerated()), id: \.offset) { _, issue in
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Line \(issue.line)", comment: "Prefix of a configuration file warning, row in Settings > Advanced; the number is the line in the file."))
              .font(.callout)
              .monospacedDigit()
              .foregroundStyle(.secondary)
            Text(issue.message)
              .multilineTextAlignment(.leading)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
}
