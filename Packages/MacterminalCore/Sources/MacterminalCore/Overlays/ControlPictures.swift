/// Muestra los caracteres de control como glifos visibles para que un texto ajeno (la sugerencia
/// de la IA) se lea tal cual sin que la vista lo interprete: `\n` no parte la línea y `ESC` no
/// desaparece.
public enum ControlPictures {
  public static func visible(_ text: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      scalars.append(picture(for: scalar))
    }
    return String(scalars)
  }

  private static func picture(for scalar: Unicode.Scalar) -> Unicode.Scalar {
    switch scalar.value {
    // Bloque "Control Pictures": U+2400 + código para C0 y U+2421 para DEL.
    case 0x00..<0x20: Unicode.Scalar(0x2400 + scalar.value) ?? replacement
    case 0x7F: "\u{2421}"
    case 0x80...0x9F: replacement
    default: scalar
    }
  }

  private static let replacement: Unicode.Scalar = "\u{FFFD}"
}
