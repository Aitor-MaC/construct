import Foundation

public enum LinkDecision: Sendable, Equatable {
  case open, revealInFinder, reject
}

/// Qué hacer con un enlace de la salida del terminal (I1). La URL la escribe cualquier programa:
/// solo se abren esquemas que el navegador o Mail manejan sin ejecutar nada, y un archivo local se
/// enseña en el Finder en lugar de abrirse (un `.command` se ejecutaría).
public enum LinkPolicy {
  public static func decide(_ url: URL, localHostName: String = currentHostName) -> LinkDecision {
    switch url.scheme?.lowercased() {
    case "http", "https": hasHost(url) ? .open : .reject
    case "mailto": .open
    case "file": isLocal(url, localHostName: localHostName) ? .revealInFinder : .reject
    default: .reject
    }
  }

  /// El mismo nombre que `hostname`, que es el que escriben `ls --hyperlink`, eza, fd o rg.
  public static var currentHostName: String {
    var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
    guard gethostname(&buffer, buffer.count - 1) == 0 else { return "localhost" }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  private static func hasHost(_ url: URL) -> Bool {
    !(url.host(percentEncoded: false) ?? "").isEmpty
  }

  /// Un host remoto en `file://` lo montaría el sistema (SMB/AFP) al revelarlo; el nombre de este
  /// Mac (con o sin `.local`) es local.
  private static func isLocal(_ url: URL, localHostName: String) -> Bool {
    switch url.host(percentEncoded: false)?.lowercased() {
    case .none, "", "localhost": true
    case .some(let host): bareHostName(host) == bareHostName(localHostName.lowercased())
    }
  }

  private static func bareHostName(_ host: String) -> String {
    host.hasSuffix(".local") ? String(host.dropLast(".local".count)) : host
  }
}
