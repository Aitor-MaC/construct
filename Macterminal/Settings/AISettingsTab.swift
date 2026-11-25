import AppKit
import MacterminalCore
import SwiftUI

/// IA: disponibilidad de Apple Intelligence para las sugerencias `# …`, con el motivo si falta.
struct AISettingsTab: View {
  let suggester: CommandSuggester
  /// `nil` mientras se comprueba: nunca se da por disponible ni por no disponible sin preguntar.
  @State private var availability: SuggestionAvailability?
  /// Motivo en bruto cuando no está disponible; decide si se vuelve a comprobar sola.
  @State private var reason: ModelAvailabilityReason?

  /// Cada cuánto se vuelve a preguntar mientras el modelo se descarga o falta activarlo.
  private static let pollInterval = Duration.seconds(5)
  /// Panel «Apple Intelligence y Siri» de Ajustes del Sistema.
  private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")

  var body: some View {
    Form {
      Section {
        LabeledContent(String(localized: "Apple Intelligence", comment: "Row label in Settings > AI. Apple's product name; keep it.")) { status }
        if reason?.isTransient == true {
          Button(
            String(localized: "Open Apple Intelligence Settings…", comment: "Button in Settings > AI that opens the Apple Intelligence & Siri pane of System Settings."),
            action: openSystemSettings)
        }
        Button(String(localized: "Check Again", comment: "Button in Settings > AI that asks the system again whether Apple Intelligence is available."), action: refresh)
          .disabled(availability == nil)
      } footer: {
        VStack(alignment: .leading, spacing: 6) {
          if reason == .modelNotReady {
            Text(
              String(
                localized: "macOS downloads the model automatically when the Mac is on Wi-Fi and power. This status updates by itself when it’s ready.",
                comment: "Footer in Settings > AI while the Apple Intelligence model is still downloading.")
            )
          }
          Text(
            String(
              localized: "Type # or ?? followed by what you want, for example “#install powershell with homebrew”. Construct suggests a command that you review before running it. Everything is processed on this Mac.",
              comment: "Explanation in Settings > AI of how to ask for a command suggestion. Keep the # and ?? characters.")
          )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: SettingsLayout.width, height: 300)
    // Comprueba al aparecer y, mientras el motivo sea pasajero, cada pocos segundos.
    // `.task` se cancela solo al cerrar la pestaña o la ventana de Ajustes.
    .task {
      refresh()
      while reason?.isTransient == true {
        do { try await Task.sleep(for: Self.pollInterval) } catch { return }
        refresh()
      }
    }
  }

  @ViewBuilder private var status: some View {
    switch availability {
    case nil:
      ProgressView().controlSize(.small)
        .accessibilityLabel(String(localized: "Checking availability", comment: "VoiceOver label of the progress spinner in Settings > AI while availability is checked."))
    case .available:
      Label(String(localized: "Available", comment: "AI availability status in Settings > AI: Apple Intelligence can be used."), systemImage: "checkmark.circle.fill")
        .foregroundStyle(.tint)
    case .unavailable(let reasonText):
      VStack(alignment: .trailing, spacing: 2) {
        Label(String(localized: "Not available", comment: "AI availability status in Settings > AI: Apple Intelligence cannot be used."), systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(reasonText)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.trailing)
      }
      .accessibilityElement(children: .combine)
    }
  }

  private func refresh() {
    let result = suggester.availabilityWithReason()
    availability = result.availability
    reason = result.reason
  }

  private func openSystemSettings() {
    // Si el panel concreto no se puede abrir, al menos abre Ajustes del Sistema.
    if let url = Self.systemSettingsURL, NSWorkspace.shared.open(url) { return }
    if let fallback = URL(string: "x-apple.systempreferences:") { NSWorkspace.shared.open(fallback) }
  }
}
