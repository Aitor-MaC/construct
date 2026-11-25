import Foundation

/// Claves del archivo de configuración (`~/.config/macterminal/config`).
public enum ConfigKey: String, Sendable, CaseIterable {
  case fontFamily = "font-family"
  case fontSize = "font-size"
  case intensity
  case prompt
  case autosuggest
  case backgroundOpacity = "background-opacity"
  case quakeHotkey = "quake-hotkey"
  case shell
  case greetingName = "greeting-name"
  case promptUserHost = "prompt-user-host"
  case promptPath = "prompt-path"

  public enum Application: Sendable, Equatable {
    /// Se aplica a los paneles abiertos al recargar.
    case immediately
    /// Solo afecta a las sesiones que se abran después.
    case newSessions
  }

  public var appliesTo: Application {
    switch self {
    case .prompt, .autosuggest, .promptUserHost, .promptPath, .shell: .newSessions
    case .fontFamily, .fontSize, .intensity, .backgroundOpacity, .quakeHotkey, .greetingName:
      .immediately
    }
  }
}

/// Aviso de lectura de la configuración; `line` es 1-based.
public struct ConfigIssue: Sendable, Equatable {
  public var line: Int
  public var key: String?
  public var message: String
  public init(line: Int, key: String?, message: String) {
    self.line = line
    self.key = key
    self.message = message
  }
}
