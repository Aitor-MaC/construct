import SwiftUI

/// Aviso de una línea arriba del lienzo cuando la integración de shell no responde: la terminal
/// sigue funcionando, solo que sin bloques. El botón "Añadir" del diseño queda fuera de T10.
struct IntegrationBannerView: View {
  enum Cause {
    /// La shell no es zsh o no se pudo instalar la integración.
    case unsupportedShell
    /// Es zsh, pero no llegó ninguna marca A a tiempo: algo en la configuración del usuario la pisa.
    case noPromptMark
  }

  let cause: Cause
  let onDismiss: () -> Void

  private var message: String {
    switch cause {
    case .unsupportedShell:
      String(localized: "Blocks aren’t available: the integration only works with zsh. Check the shell in Settings > Advanced.", comment: "Banner shown above the terminal when the command blocks feature is off because the shell isn't zsh. A block is one command with its output.")
    case .noPromptMark:
      String(localized: "The zsh integration didn’t start. Check whether your .zshrc overrides precmd or preexec.", comment: "Banner shown when the shell integration script did not report a prompt. .zshrc, precmd and preexec are zsh names; do not translate them.")
    }
  }

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "square.stack.3d.up.slash")
        .foregroundStyle(BlockTokens.muted)
        .accessibilityHidden(true)
      Text(message)
        .foregroundStyle(BlockTokens.text)
        .lineLimit(1)
        .truncationMode(.tail)
        .help(message)
      Spacer(minLength: 8)
      Button(action: onDismiss) {
        Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
      }
      .buttonStyle(BlockActionButtonStyle())
      .accessibilityLabel(String(localized: "Dismiss Notice", comment: "VoiceOver label of the X button that hides the integration banner."))
    }
    .font(.system(size: 12))
    .padding(.horizontal, 16)
    .frame(height: 28)
    .frame(maxWidth: .infinity)
    .background(BlockTokens.surface2)
    .overlay(alignment: .bottom) { BlockTokens.hairStrong.frame(height: 0.5) }
    .accessibilityElement(children: .contain)
  }
}
