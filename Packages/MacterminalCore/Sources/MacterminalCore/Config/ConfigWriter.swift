import Foundation

/// Edición textual del archivo de configuración conservando comentarios, orden y líneas ajenas.
public enum ConfigWriter {
  public static func setting(_ key: ConfigKey, to value: String, in text: String) -> String {
    var lines = ConfigLines.split(text)
    let clean = sanitize(value)
    let replacement = Substring("\(key.rawValue) = \(format(clean))")

    if let index = lines.lastIndex(where: {
      ConfigLines.assignment(in: $0.content)?.key == key.rawValue
    }) {
      if let existing = ConfigLines.assignment(in: lines[index].content),
        ConfigParser.unquote(existing.value) == clean
      {
        return text
      }
      lines[index].content = replacement
      return join(lines)
    }

    let newline = lines.first(where: { !$0.terminator.isEmpty })?.terminator ?? "\n"
    let last = lines.count - 1
    if lines[last].content.isEmpty {
      // Texto vacío o acabado en salto de línea: la clave va en esa última línea.
      lines[last] = ConfigLines.Line(content: replacement, terminator: newline)
      lines.append(ConfigLines.Line(content: "", terminator: ""))
    } else {
      lines[last].terminator = newline
      lines.append(ConfigLines.Line(content: replacement, terminator: newline))
      lines.append(ConfigLines.Line(content: "", terminator: ""))
    }
    return join(lines)
  }

  /// Quita todas las asignaciones de `key` (también las repetidas); comentarios y demás líneas
  /// se quedan como estaban. Sin la clave, devuelve el texto intacto.
  public static func removing(_ key: ConfigKey, in text: String) -> String {
    let lines = ConfigLines.split(text)
    let kept = lines.filter { ConfigLines.assignment(in: $0.content)?.key != key.rawValue }
    return kept.count == lines.count ? text : join(kept)
  }

  private static func join(_ lines: [ConfigLines.Line]) -> String {
    lines.map { $0.content + $0.terminator }.joined()
  }

  /// Sustituye saltos de línea y controles por espacios: un valor no puede inyectar otras claves.
  private static func sanitize(_ value: String) -> String {
    var out = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      let isBreak =
        scalar.properties.generalCategory == .control || scalar == "\u{2028}"
        || scalar == "\u{2029}"
      out.append(isBreak ? " " : scalar)
    }
    return String(out).trimmingCharacters(in: .whitespaces)
  }

  private static func format(_ clean: String) -> String {
    guard clean.contains(where: { $0 == " " || $0 == "#" || $0 == "\"" || $0 == "'" }) else {
      return clean
    }
    if !clean.contains("\"") { return "\"\(clean)\"" }
    if !clean.contains("'") { return "'\(clean)'" }
    return "\"\(clean.replacingOccurrences(of: "\"", with: ""))\""
  }
}
