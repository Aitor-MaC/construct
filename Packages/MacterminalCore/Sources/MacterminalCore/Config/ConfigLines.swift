import Foundation

/// Partición de líneas y extracción de clave compartidas por el parser y el writer.
enum ConfigLines {
  struct Line {
    var content: Substring
    var terminator: Substring
  }

  /// Parte por cualquier salto de línea (`\n`, `\r\n`, `\r`, U+2028...) conservando el terminador.
  /// El último elemento es el resto tras el último terminador (vacío si el texto acaba en salto).
  static func split(_ text: String) -> [Line] {
    var lines: [Line] = []
    var start = text.startIndex
    var index = start
    while index < text.endIndex {
      let next = text.index(after: index)
      if text[index].isNewline {
        lines.append(Line(content: text[start..<index], terminator: text[index..<next]))
        start = next
      }
      index = next
    }
    lines.append(Line(content: text[start...], terminator: ""))
    return lines
  }

  /// Clave y valor sin procesar de una línea `clave = valor`; `nil` en vacías y comentarios.
  static func assignment(in content: Substring) -> (key: String, value: String)? {
    let line = content.trimmingCharacters(in: .whitespaces)
    guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else {
      return nil
    }
    return (
      line[..<eq].trimmingCharacters(in: .whitespaces),
      line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
    )
  }
}
