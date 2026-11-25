import AppKit
import MacterminalCore
import SwiftUI

/// Piezas visuales compartidas por la barra de búsqueda, la tarjeta de la IA y el toast
/// (dirección de diseño §4.3, §4.6 y §5).
enum OverlayStyle {
  static let surface = MatrixTheme.color(MatrixPalette.surface2)
  static let border = MatrixTheme.color(MatrixPalette.hairStrong, alpha: MatrixPalette.hairStrongAlpha)
  static let focusRing = MatrixTheme.color(MatrixPalette.ph400)
  static let commandFont = Font(
    FontLoader.terminalFont(family: TerminalConfig().fontFamily, size: 13) as CTFont)
  /// Entrada y salida de flotantes: 180 ms, ease-out.
  static let enterExit = Animation.easeOut(duration: 0.18)
  /// Pulsación: 120 ms con `cubic-bezier(.23,1,.32,1)`.
  static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
  static let hover = Animation.easeInOut(duration: 0.12)
}

extension View {
  /// Sombra de los flotantes: `0 4 16 black/40%, 0 24 60 black/50%` (el contorno de 0,5 pt lo
  /// pone cada flotante con su radio).
  func floatingShadow() -> some View {
    shadow(color: .black.opacity(0.4), radius: 8, y: 4)
      .shadow(color: .black.opacity(0.5), radius: 30, y: 24)
  }
}

/// Botón de los flotantes: reposo, hover, pulsado (escala 0,97 salvo con Reduce Motion), foco
/// (anillo de 2 pt `ph400`) y deshabilitado (`faint`).
struct OverlayButtonStyle: ButtonStyle {
  enum Kind { case primary, secondary, icon }
  let kind: Kind

  func makeBody(configuration: Configuration) -> some View {
    OverlayButtonBody(configuration: configuration, kind: kind)
  }
}

private struct OverlayButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let kind: OverlayButtonStyle.Kind
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.isFocused) private var isFocused
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false

  var body: some View {
    configuration.label
      .font(.system(size: 13, weight: kind == .primary ? .medium : .regular))
      .foregroundStyle(foreground)
      .padding(.horizontal, kind == .icon ? 0 : 10)
      .frame(minWidth: kind == .icon ? 22 : nil, minHeight: kind == .icon ? 22 : 26)
      .background(background, in: .rect(cornerRadius: 6))
      .overlay {
        if isFocused {
          RoundedRectangle(cornerRadius: 6).strokeBorder(OverlayStyle.focusRing, lineWidth: 2)
        }
      }
      .contentShape(.rect(cornerRadius: 6))
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
      .animation(OverlayStyle.press, value: configuration.isPressed)
      .animation(OverlayStyle.hover, value: isHovered)
      .onHover { isHovered = $0 }
  }

  private var foreground: Color {
    guard isEnabled else { return MatrixTheme.color(MatrixPalette.faint) }
    switch kind {
    case .primary: return MatrixTheme.color(MatrixPalette.bg)
    case .secondary: return MatrixTheme.color(MatrixPalette.fg)
    case .icon: return MatrixTheme.color(isHovered ? MatrixPalette.fgBright : MatrixPalette.muted)
    }
  }

  private var background: Color {
    guard isEnabled else { return .clear }
    switch kind {
    case .primary:
      return MatrixTheme.color(isHovered ? MatrixPalette.ph200 : MatrixPalette.ph400)
    case .secondary, .icon:
      return isHovered || configuration.isPressed
        ? MatrixTheme.color(MatrixPalette.surface3) : .clear
    }
  }
}

/// Tecla dibujada junto a una acción (`⏎`, `esc`), como los keycaps de la paleta.
struct Keycap: View {
  let symbol: String
  var onAccent = false

  var body: some View {
    Text(verbatim: symbol)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(
        onAccent ? MatrixTheme.color(MatrixPalette.bg) : MatrixTheme.color(MatrixPalette.fg))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(
        onAccent
          ? MatrixTheme.color(MatrixPalette.bg, alpha: 0.14) : MatrixTheme.color(MatrixPalette.surface3),
        in: .rect(cornerRadius: 4)
      )
      .accessibilityHidden(true)
  }
}
