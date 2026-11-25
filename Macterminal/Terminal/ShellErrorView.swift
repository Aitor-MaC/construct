import MacterminalCore
import MacterminalTerminal
import SwiftUI

/// Lo que queda en el panel cuando el shell no arranca (I8): el motivo y la salida posible.
struct ShellErrorView: View {
  enum Failure: Equatable {
    /// El shell terminó antes de su primer prompt; con integración se puede reintentar sin ella.
    case exitedAtStartup(message: String, canRetryWithoutIntegration: Bool)
    case shellNotFound(message: String)
  }

  let failure: Failure
  let onRetryWithoutIntegration: () -> Void
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(message, systemImage: "exclamationmark.triangle")
        .font(.headline)
        .foregroundStyle(MatrixTheme.color(MatrixPalette.fgBright))
      HStack(spacing: 8) {
        if canRetry {
          Button(String(localized: "Retry Without Integration", comment: "Button shown when the zsh integration failed: starts the shell again without command blocks."), action: onRetryWithoutIntegration)
            .keyboardShortcut(.defaultAction)
        }
        Button(String(localized: "Open Settings", comment: "Action in the toast or menu that opens the Settings window.")) { openSettings() }
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(MatrixTheme.color(MatrixPalette.bg))
    .accessibilityElement(children: .contain)
  }

  private var message: String {
    switch failure {
    case .exitedAtStartup(let message, _), .shellNotFound(let message): message
    }
  }

  private var canRetry: Bool {
    if case .exitedAtStartup(_, true) = failure { return true }
    return false
  }
}

#Preview("Failed launch") {
  ShellErrorView(
    failure: .exitedAtStartup(
      message: StartupFailurePolicy.message(exitCode: 1), canRetryWithoutIntegration: true),
    onRetryWithoutIntegration: {})
}

#Preview("Missing shell") {
  ShellErrorView(
    failure: .shellNotFound(
      message: ShellLaunchError.shellNotFound("/no/existe").localizedDescription),
    onRetryWithoutIntegration: {})
}
