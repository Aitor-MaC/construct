import Foundation

/// Posición de la coincidencia actual dentro de todas las de la búsqueda, como la devuelve
/// `TerminalView.searchMatchSummary` de SwiftTerm: `index` base 1 (0 = ninguna seleccionada) y
/// `total` acotado a `limit`.
public struct FindMatchSummary: Sendable, Equatable {
  public let index: Int
  public let total: Int
  /// `true` cuando SwiftTerm dejó de contar al llegar a `limit`: el total real puede ser mayor.
  public let isCapped: Bool

  public init(index: Int, total: Int, limit: Int) {
    let total = max(0, total)
    self.total = total
    self.index = min(max(0, index), total)
    isCapped = limit > 0 && total >= limit
  }

  public var hasMatches: Bool { total > 0 }

  /// Texto del contador. Sin coincidencias nunca se lee "0 de 0".
  public var label: String {
    guard hasMatches else {
      return String(
        localized: "No matches", bundle: .localized, comment: "Find bar counter when nothing matches.")
    }
    // Cifras sin separador de miles, iguales en cualquier región: el contador es estrecho y la
    // interpolación localizada escribiría "1,000" o "1.000" según el sistema.
    let index = String(index)
    let total = String(total)
    if self.index > 0 {
      return isCapped
        ? String(
          localized: "\(index) of more than \(total)", bundle: .localized,
          comment:
            "Find bar counter when the count is capped; the placeholders are the current match and the cap."
        )
        : String(
          localized: "\(index) of \(total)", bundle: .localized,
          comment: "Find bar counter; the placeholders are the current match and the total.")
    }
    if isCapped {
      return String(
        localized: "More than \(total) matches", bundle: .localized,
        comment: "Find bar counter when the count is capped and no match is selected.")
    }
    return self.total == 1
      ? String(
        localized: "1 match", bundle: .localized, comment: "Find bar counter with exactly one match.")
      : String(
        localized: "\(total) matches", bundle: .localized,
        comment: "Find bar counter with several matches; the placeholder is always 2 or more.")
  }
}

/// Texto inicial de la barra de búsqueda a partir de la selección de la terminal.
public enum FindQuery {
  /// La búsqueda de SwiftTerm es por línea; una selección enorme no aporta nada al campo.
  public static let maxPrefillCharacters = 200

  /// Primera línea no vacía de la selección, sin caracteres de control (el tabulador pasa a
  /// espacio) y recortada a `maxPrefillCharacters` grafemas. `nil` si no queda texto.
  public static func prefill(fromSelection selection: String?) -> String? {
    guard let selection else { return nil }
    let firstLine = selection.split(whereSeparator: \.isNewline)
      .lazy
      .map { cleaned($0) }
      .first { !$0.isEmpty }
    guard let firstLine else { return nil }
    return String(firstLine.prefix(maxPrefillCharacters))
  }

  private static func cleaned(_ line: Substring) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in line.unicodeScalars {
      if scalar == "\t" {
        scalars.append(" ")
      } else if scalar.properties.generalCategory != .control {
        scalars.append(scalar)
      }
    }
    return String(scalars).trimmingCharacters(in: .whitespaces)
  }
}
