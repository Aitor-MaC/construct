import Foundation

/// Literales de shell para el texto que la paleta escribe en el prompt (nunca lo ejecuta).
public enum ShellLiteral {
  /// Comillas simples POSIX: dentro no se expande nada; cada `'` se cierra, se escapa y se reabre.
  public static func singleQuoted(_ raw: String) -> String {
    "'" + raw.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  /// `cd '<ruta>'` sin retorno final: la persona decide si lo ejecuta.
  public static func changeDirectory(to url: URL) -> String {
    "cd " + singleQuoted(url.path(percentEncoded: false))
  }
}
