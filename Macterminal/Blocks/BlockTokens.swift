import MacterminalCore
import SwiftUI

/// Tokens de la dirección de diseño (§4.1, §5) que usan los bloques, ya convertidos a `Color`.
enum BlockTokens {
  static let hair = MatrixTheme.color(MatrixPalette.hair, alpha: MatrixPalette.hairAlpha)
  static let hairStrong = MatrixTheme.color(
    MatrixPalette.hairStrong, alpha: MatrixPalette.hairStrongAlpha)
  static let accent = MatrixTheme.color(MatrixPalette.ph400)
  static let accentSoft = MatrixTheme.color(MatrixPalette.ph200)
  static let background = MatrixTheme.color(MatrixPalette.bg)
  static let surface1 = MatrixTheme.color(MatrixPalette.surface1)
  static let surface1Hover = MatrixTheme.color(MatrixPalette.surface1, alpha: 0.55)
  static let surface2 = MatrixTheme.color(MatrixPalette.surface2)
  static let surface3 = MatrixTheme.color(MatrixPalette.surface3)
  static let errorTint = MatrixTheme.color(MatrixPalette.errTint, alpha: MatrixPalette.errTintAlpha)
  static let text = MatrixTheme.color(MatrixPalette.fg)
  static let textBright = MatrixTheme.color(MatrixPalette.fgBright)
  static let muted = MatrixTheme.color(MatrixPalette.muted)
  static let faint = MatrixTheme.color(MatrixPalette.faint)
  static let success = MatrixTheme.color(MatrixPalette.ansi[2])
  static let failureText = MatrixTheme.color(MatrixPalette.ansi[9])
  /// El fondo del chip de error (`#3A1513` en el mock) no es un token de `MatrixPalette`: se
  /// obtiene del rojo ANSI 1 al 18 % sobre `bg`, que da el mismo tono y 7,4:1 con ANSI 9.
  static let failureFill = MatrixTheme.color(MatrixPalette.ansi[1], alpha: 0.18)

  static let hover = Animation.easeInOut(duration: 0.12)
  static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
  static let enter = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
  /// Salida más corta que la entrada: lo que se va no debe hacer esperar.
  static let exit = Animation.easeOut(duration: 0.15)
}
