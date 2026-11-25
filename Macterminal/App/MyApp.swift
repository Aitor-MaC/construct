import SwiftUI

@main struct MyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
  var body: some Scene {
    Settings {
      SettingsView()
        .environment(delegate.workspace.configStore)
        .environment(\.configFileURL, delegate.workspace.configURL)
    }
    .commands { AppCommands(registry: .shared, settingsOpener: delegate.workspace.settingsOpener) }
  }
}
