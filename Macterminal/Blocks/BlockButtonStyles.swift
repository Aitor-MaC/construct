import SwiftUI

/// Botón pequeño de la cabecera de un bloque (Copiar, Copiar salida, Repetir): `surface2`,
/// `surface3` al pasar, escala 0,97 al pulsar, anillo de 2 pt `ph400` con el foco y texto
/// `faint` deshabilitado.
struct BlockActionButtonStyle: ButtonStyle {
  var confirmed = false

  func makeBody(configuration: Configuration) -> some View {
    BlockActionButton(configuration: configuration, confirmed: confirmed)
  }

  private struct BlockActionButton: View {
    let configuration: ButtonStyleConfiguration
    let confirmed: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
      configuration.label
        .font(.system(size: 11))
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .frame(height: 18)
        .background(isHovered && isEnabled ? BlockTokens.surface3 : BlockTokens.surface2, in: .rect(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(BlockTokens.hairStrong, lineWidth: 0.5) }
        .overlay {
          if isFocused {
            RoundedRectangle(cornerRadius: 6).strokeBorder(BlockTokens.accent, lineWidth: 2).padding(-1)
          }
        }
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .animation(BlockTokens.press, value: configuration.isPressed)
        .animation(BlockTokens.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var foreground: Color {
      guard isEnabled else { return BlockTokens.faint }
      return confirmed ? BlockTokens.accentSoft : BlockTokens.text
    }
  }
}

/// Acción principal del estado vacío: fondo `ph400`, texto `bg`, 28 pt de alto y radio 6;
/// deshabilitada, `surface2` con texto `faint`.
struct BlockPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PrimaryButton(configuration: configuration)
  }

  private struct PrimaryButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isEnabled ? BlockTokens.background : BlockTokens.faint)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(isEnabled ? BlockTokens.accent : BlockTokens.surface2, in: .rect(cornerRadius: 6))
        .brightness(isHovered && isEnabled ? 0.08 : 0)
        .overlay {
          if isFocused {
            RoundedRectangle(cornerRadius: 8).strokeBorder(BlockTokens.accent, lineWidth: 2).padding(-3)
          }
        }
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .animation(BlockTokens.press, value: configuration.isPressed)
        .animation(BlockTokens.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
  }
}
