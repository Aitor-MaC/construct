/// Títulos OSC 0/1/2: los escribe cualquier programa, así que se quedan en texto visible de una
/// línea (I2). Un título con `\n` que luego se reflejara en un informe sería una inyección en la
/// entrada del shell.
public enum TitleSanitizer {
  public static let maxCharacters = 80

  public static func clean(_ raw: String) -> String {
    var visible = String.UnicodeScalarView()
    for scalar in raw.unicodeScalars where !isInvisible(scalar) {
      visible.append(scalar)
    }
    let trimmed = String(visible).trimmingCharacters(in: .whitespaces)
    return String(trimmed.prefix(maxCharacters))
  }

  /// Cc (C0, DEL, C1), Cf (bidi, ancho cero, BOM) y separadores de línea y párrafo.
  private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .format, .lineSeparator, .paragraphSeparator: true
    default: false
    }
  }
}
