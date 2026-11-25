import Foundation

public enum InsertionRejection: Error, LocalizedError, Sendable, Equatable {
  case controlCharacter, bidiControl, invisibleCharacter, tooLong

  public var errorDescription: String? {
    switch self {
    case .controlCharacter:
      String(
        localized:
          "The text contains line breaks or control characters and can’t be written to the prompt.",
        bundle: .localized, comment: "Error shown when text can't be inserted into the shell prompt.")
    case .bidiControl:
      String(
        localized:
          "The text contains invisible characters that change the reading direction and can’t be written to the prompt.",
        bundle: .localized, comment: "Error shown when text can't be inserted into the shell prompt.")
    case .invisibleCharacter:
      String(
        localized:
          "The text contains invisible characters or Unicode line breaks and can’t be written to the prompt.",
        bundle: .localized, comment: "Error shown when text can't be inserted into the shell prompt.")
    case .tooLong:
      String(
        localized: "The text is too long to write to the prompt.", bundle: .localized,
        comment: "Error shown when text can't be inserted into the shell prompt.")
    }
  }
}

/// Única puerta de validación para texto que la app escribe en el prompt (IA, historial,
/// Repetir, paleta). Rechaza en lugar de limpiar: lo que se inserta es exactamente lo que se
/// validó, y un salto de línea no puede ejecutar nada (A8).
public enum PromptInsertion {
  public static let maxUTF8Length = 4096

  public static func validate(_ text: String) -> Result<String, InsertionRejection> {
    guard text.utf8.count <= maxUTF8Length else { return .failure(.tooLong) }
    for scalar in text.unicodeScalars {
      if scalar.isForbiddenControl { return .failure(.controlCharacter) }
      if scalar.isBidiControl { return .failure(.bidiControl) }
      if scalar.isZeroWidth || scalar.isUnicodeLineBreak { return .failure(.invisibleCharacter) }
    }
    return .success(text)
  }
}

extension Unicode.Scalar {
  /// C0 salvo tab (incluye ESC, CR y LF), DEL y C1 (incluye CSI 0x9B de 8 bits).
  var isForbiddenControl: Bool {
    switch value {
    case 0x09: false
    case 0x00...0x1F, 0x7F...0x9F: true
    default: false
    }
  }

  /// Embeddings, overrides e isolates: reordenan visualmente el texto (S1, "Trojan Source").
  var isBidiControl: Bool {
    switch value {
    case 0x202A...0x202E, 0x2066...0x2069: true
    default: false
    }
  }

  /// U+2028/U+2029: zsh no los trata como fin de línea, pero la interfaz sí los pinta como salto.
  var isUnicodeLineBreak: Bool {
    value == 0x2028 || value == 0x2029
  }

  /// Espacios de ancho cero, ZWJ/ZWNJ, marcas LRM/RLM y BOM: invisibles en pantalla.
  var isZeroWidth: Bool {
    switch value {
    case 0x200B...0x200F, 0xFEFF: true
    default: false
    }
  }
}
