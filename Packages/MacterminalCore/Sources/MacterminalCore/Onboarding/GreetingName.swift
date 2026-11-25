import Foundation

/// Nombre del saludo "Wake up, {nombre}…": viene del config o de macOS y se pinta tal cual en
/// el lienzo, así que nunca lleva controles, bidi ni caracteres invisibles.
public enum GreetingName {
  public static let maxLength = 32

  /// Recorta, quita controles y caracteres de formato (ESC, bidi, ancho cero, BOM), convierte
  /// saltos de línea y tabuladores en espacios, colapsa los espacios y corta a 32 grafemas.
  /// `nil` si no queda nada.
  public static func sanitize(_ raw: String) -> String? {
    var scalars = String.UnicodeScalarView()
    for scalar in raw.unicodeScalars {
      // Un salto de línea o un tabulador separa palabras: "Thomas\nAnderson" no debe pegarse.
      if scalar.properties.isWhitespace {
        scalars.append(" ")
        continue
      }
      switch scalar.properties.generalCategory {
      case .control, .format: continue
      default: scalars.append(scalar)
      }
    }
    let words = String(scalars).split(whereSeparator: \.isWhitespace)
    let collapsed = words.joined(separator: " ").prefix(maxLength)
    let trimmed = collapsed.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// El del config si sobrevive al saneado; si no, el nombre de pila de macOS; si tampoco,
  /// `nil` y el saludo queda en "Wake up…".
  public static func resolve(configured: String?, systemGivenName: String?) -> String? {
    configured.flatMap(sanitize) ?? systemGivenName.flatMap(sanitize)
  }
}
