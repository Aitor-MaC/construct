import MacterminalCore
import SwiftUI

/// Pie de sección para las claves que no cambian las sesiones abiertas (A4).
struct AppliesToNote: View {
  let key: ConfigKey

  var body: some View {
    if key.appliesTo == .newSessions {
      Label(String(localized: "Applies to new tabs and panes", comment: "Note in Settings: the change only affects tabs and panes opened afterwards."), systemImage: "info.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
