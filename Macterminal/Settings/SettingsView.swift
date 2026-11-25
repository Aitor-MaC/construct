import MacterminalCore
import SwiftUI

extension EnvironmentValues {
  /// Ruta de `~/.config/macterminal/config` que usa el `ConfigStore` inyectado (la pone T14).
  @Entry var configFileURL: URL? = nil
}

/// Escena `Settings`: edita el archivo de configuración solo a través de `ConfigStore.set`.
/// El store y la ruta llegan por el entorno; sin store, la ventana explica que no hay ajustes.
struct SettingsView: View {
  @Environment(ConfigStore.self) private var store: ConfigStore?
  @Environment(\.configFileURL) private var configFileURL
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var toastMessage: String?
  private let suggester: CommandSuggester

  init(suggester: CommandSuggester = CommandSuggester()) {
    self.suggester = suggester
  }

  var body: some View {
    if let store {
      tabs(store)
        .overlay(alignment: .bottom) { toast }
        .task(id: toastMessage) { await dismissToastLater() }
    } else {
      ContentUnavailableView(
        String(localized: "Settings Unavailable", comment: "Title of the Settings window when the configuration store is unavailable."), systemImage: "gearshape",
        description: Text(String(localized: "Construct’s configuration couldn’t be loaded.", comment: "Description of the Settings window when the configuration store is unavailable.")))
        .frame(width: SettingsLayout.width, height: 240)
    }
  }

  private func tabs(_ store: ConfigStore) -> some View {
    let save = ConfigSave(store: store) { message in showToast(message) }
    return TabView {
      Tab(String(localized: "Appearance", comment: "Tab title in the Settings window for visual options (rain, font, greeting)."), systemImage: "paintbrush") {
        AppearanceSettingsTab(config: store.config, save: save)
      }
      Tab(String(localized: "Prompt", comment: "Tab title in the Settings window for the shell prompt options. “Prompt” is the line where you type a command."), systemImage: "chevron.forward.square") {
        PromptSettingsTab(config: store.config, save: save)
      }
      Tab(String(localized: "Keyboard", comment: "Tab title in the Settings window for keyboard shortcuts."), systemImage: "keyboard") {
        KeyboardSettingsTab(config: store.config, save: save)
      }
      Tab(String(localized: "AI", comment: "Tab title in the Settings window for the AI suggestions options."), systemImage: "sparkles") {
        AISettingsTab(suggester: suggester)
      }
      Tab(String(localized: "Advanced", comment: "Tab title in the Settings window for advanced options (shell path, configuration file)."), systemImage: "gearshape.2") {
        AdvancedSettingsTab(
          store: store, configFileURL: configFileURL, save: save, onError: showToast)
      }
    }
  }

  @ViewBuilder private var toast: some View {
    if let toastMessage {
      Label(toastMessage, systemImage: "exclamationmark.triangle.fill")
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .capsule)
        .padding(.bottom, 16)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityAddTraits(.isStaticText)
    }
  }

  private func showToast(_ message: String) {
    withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
    AccessibilityNotification.Announcement(message).post()
  }

  private func dismissToastLater() async {
    guard toastMessage != nil else { return }
    do { try await Task.sleep(for: .seconds(4)) } catch { return }
    withAnimation(.easeOut(duration: 0.2)) { toastMessage = nil }
  }
}

/// Tamaño fijo de cada pestaña: la ventana no crece con el contenido.
enum SettingsLayout {
  static let width: CGFloat = 520
}

/// Única vía de escritura de los ajustes. Si `set` falla, avisa con un toast; los controles leen
/// de `store.config`, así que vuelven solos al valor guardado.
@MainActor struct ConfigSave {
  let store: ConfigStore
  let onError: (String) -> Void

  @discardableResult
  func callAsFunction(_ key: ConfigKey, _ value: String) -> Bool {
    do {
      try store.set(key, value)
      return true
    } catch {
      onError(error.localizedDescription)
      return false
    }
  }

  /// Borra la clave del archivo para volver a su valor por defecto.
  @discardableResult
  func remove(_ key: ConfigKey) -> Bool {
    do {
      try store.remove(key)
      return true
    } catch {
      onError(error.localizedDescription)
      return false
    }
  }
}
