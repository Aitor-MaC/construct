import Foundation
import MacterminalCore
import SwiftUI

/// Escenario de las previews: un `ConfigStore` real sobre un archivo temporal propio, con el
/// texto escrito por `ConfigWriter` (el productor real del archivo).
@MainActor private func settingsPreview(
  _ settings: [(ConfigKey, String)] = [],
  availability: ModelAvailability = .available
) -> some View {
  let folder = FileManager.default.temporaryDirectory
    .appending(path: "settings-preview-\(UUID().uuidString)")
  let file = folder.appending(path: "config")
  var text = ""
  for (key, value) in settings { text = ConfigWriter.setting(key, to: value, in: text) }
  do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try text.write(to: file, atomically: true, encoding: .utf8)
  } catch {
    preconditionFailure("Preview: couldn't prepare the temporary file: \(error)")
  }
  return SettingsView(suggester: CommandSuggester(backend: PreviewBackend(state: availability)))
    .environment(ConfigStore(fileURL: file))
    .environment(\.configFileURL, file)
}

/// Solo para previews: fija la disponibilidad del modelo sin depender del Mac que las pinta.
private struct PreviewBackend: SuggestionBackend {
  let state: ModelAvailability
  func availability() -> ModelAvailability { state }
  func generate(request: String, cwd: String?) async throws -> RawSuggestion {
    throw ModelFailureError(.unknown)
  }
}

#Preview("Default · light") {
  settingsPreview().preferredColorScheme(.light)
}
#Preview("Default · dark") {
  settingsPreview().preferredColorScheme(.dark)
}
#Preview("With warnings · light") {
  settingsPreview([(.intensity, "inmersivo"), (.fontSize, "99"), (.shell, "/no/existe")])
  .preferredColorScheme(.light)
}
#Preview("With warnings · dark") {
  settingsPreview([(.intensity, "inmersivo"), (.fontSize, "99"), (.shell, "/no/existe")])
  .preferredColorScheme(.dark)
}
#Preview("AI not available · light") {
  settingsPreview(availability: .unavailable(.appleIntelligenceNotEnabled))
    .preferredColorScheme(.light)
}
#Preview("AI not available · dark") {
  settingsPreview(availability: .unavailable(.modelNotReady))
    .preferredColorScheme(.dark)
}
