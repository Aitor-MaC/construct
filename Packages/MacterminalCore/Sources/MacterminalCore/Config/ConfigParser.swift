import Foundation

/// Parser puro del formato `clave = valor`. Nunca lanza ni hace crash.
public enum ConfigParser {
  /// Tamaño máximo aceptado del archivo, en bytes.
  public static let maxFileBytes = 64 * 1024

  public static func parse(_ text: String) -> (TerminalConfig, [ConfigIssue]) {
    var config = TerminalConfig.defaults
    var issues: [ConfigIssue] = []
    guard text.utf8.count <= maxFileBytes else {
      issues.append(
        ConfigIssue(
          line: 1, key: nil,
          message: String(
            localized:
              "The configuration file is larger than 64 KB; the default values are used.",
            bundle: .localized, comment: "Configuration warning.")))
      return (config, issues)
    }
    var seen = Set<ConfigKey>()
    var lineNumber = 0
    for rawLine in ConfigLines.split(text).map(\.content) {
      lineNumber += 1
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") { continue }
      guard let (keyText, rawValue) = ConfigLines.assignment(in: rawLine) else {
        issues.append(
          ConfigIssue(
            line: lineNumber, key: nil,
            message: String(
              localized: "Line without “=”; ignored.", bundle: .localized,
              comment: "Configuration warning for a line that isn't key = value.")))
        continue
      }
      let value = unquote(rawValue)
      guard let key = ConfigKey(rawValue: keyText) else {
        issues.append(
          ConfigIssue(
            line: lineNumber, key: keyText,
            message: String(
              localized: "Unknown key “\(keyText)”; ignored.", bundle: .localized,
              comment: "Configuration warning; the placeholder is the key as written in the file."))
        )
        continue
      }
      if !seen.insert(key).inserted {
        issues.append(
          ConfigIssue(
            line: lineNumber, key: keyText,
            message: String(
              localized: "Key “\(keyText)” is repeated; the last one wins.", bundle: .localized,
              comment: "Configuration warning; the placeholder is the key as written in the file."))
        )
      }
      switch apply(key, value, to: &config) {
      case .ok: break
      case .invalid(let message), .clamped(let message):
        issues.append(ConfigIssue(line: lineNumber, key: keyText, message: message))
      }
    }
    return (config, issues)
  }

  // MARK: - Interno

  enum Outcome {
    case ok
    case invalid(String)
    case clamped(String)
  }

  static func unquote(_ value: String) -> String {
    guard value.count >= 2, let first = value.first, first == value.last,
      first == "\"" || first == "'"
    else { return value }
    return String(value.dropFirst().dropLast())
  }

  /// Número decimal estricto (admite coma decimal); rechaza `nan`, `inf`, hexadecimales y exponentes.
  static func number(_ text: String) -> Double? {
    let normalized = text.replacingOccurrences(of: ",", with: ".")
    guard !normalized.isEmpty,
      normalized.allSatisfy({ "0123456789.+-".contains($0) }),
      let value = Double(normalized), value.isFinite
    else { return nil }
    return value
  }

  static func apply(_ key: ConfigKey, _ value: String, to config: inout TerminalConfig) -> Outcome {
    let defaults = TerminalConfig.defaults
    let name = key.rawValue
    func invalid(_ detail: String) -> Outcome {
      .invalid(
        String(
          localized: "“\(name)”: \(detail); the default value is used.", bundle: .localized,
          comment:
            "Configuration warning; the placeholders are the key and the reason the value is invalid."
        ))
    }
    switch key {
    case .fontFamily:
      guard !value.isEmpty else {
        config.fontFamily = defaults.fontFamily
        return invalid(
          String(
            localized: "can’t be empty", bundle: .localized,
            comment: "Reason a configuration value is invalid; completes “key: …”."))
      }
      config.fontFamily = value
    case .fontSize:
      guard let size = number(value), (10...24).contains(size) else {
        config.fontSize = defaults.fontSize
        return invalid(
          String(
            localized: "must be a number between 10 and 24", bundle: .localized,
            comment: "Reason a configuration value is invalid; completes “key: …”."))
      }
      config.fontSize = size
    case .intensity:
      guard let intensity = Intensity(configValue: value) else {
        config.intensity = defaults.intensity
        return invalid(
          String(
            localized: "must be subtle, balanced or immersive", bundle: .localized,
            comment:
              "Reason a configuration value is invalid; completes “key: …”. The three words are the accepted intensity values."
          ))
      }
      config.intensity = intensity
    case .prompt:
      guard let flag = bool(value) else {
        config.prompt = defaults.prompt
        return invalid(
          String(
            localized: "must be true or false", bundle: .localized,
            comment:
              "Reason a configuration value is invalid; true and false are literal values, don't translate them."
          ))
      }
      config.prompt = flag
    case .autosuggest:
      guard let flag = bool(value) else {
        config.autosuggest = defaults.autosuggest
        return invalid(
          String(
            localized: "must be true or false", bundle: .localized,
            comment:
              "Reason a configuration value is invalid; true and false are literal values, don't translate them."
          ))
      }
      config.autosuggest = flag
    case .promptUserHost:
      guard let mode = PromptUserHost(rawValue: value) else {
        config.promptUserHost = defaults.promptUserHost
        return invalid(
          String(
            localized: "must be always, ssh or never", bundle: .localized,
            comment:
              "Reason a configuration value is invalid; completes “key: …”. always, ssh and never are literal values, don't translate them."
          ))
      }
      config.promptUserHost = mode
    case .promptPath:
      guard let style = PromptPath(rawValue: value) else {
        config.promptPath = defaults.promptPath
        return invalid(
          String(
            localized: "must be full or short", bundle: .localized,
            comment:
              "Reason a configuration value is invalid; completes “key: …”. full and short are literal values, don't translate them."
          ))
      }
      config.promptPath = style
    case .backgroundOpacity:
      guard let opacity = number(value) else {
        config.backgroundOpacity = defaults.backgroundOpacity
        return invalid(
          String(
            localized: "must be a number between 0.5 and 1", bundle: .localized,
            comment: "Reason a configuration value is invalid; completes “key: …”."))
      }
      config.backgroundOpacity = opacity  // el didSet recorta a 0,5...1
      if !(0.5...1).contains(opacity) {
        return .clamped(
          String(
            localized:
              "“\(name)”: out of range (0.5 to 1); set to \(config.backgroundOpacity.formatted()).",
            bundle: .localized,
            comment:
              "Configuration warning; the placeholders are the key and the value actually used."))
      }
    case .quakeHotkey:
      guard let shortcut = KeyShortcut(configString: value) else {
        config.quakeHotkey = defaults.quakeHotkey
        return invalid(
          String(
            localized: "invalid shortcut", bundle: .localized,
            comment: "Reason a configuration value is invalid; completes “key: …”."))
      }
      config.quakeHotkey = shortcut
    case .shell:
      guard isExecutableFile(value) else {
        config.shell = defaults.shell
        return invalid(
          String(
            localized: "isn’t an existing executable", bundle: .localized,
            comment: "Reason a configuration value is invalid; completes “key: …”."))
      }
      config.shell = value
    case .greetingName:
      // Vacío tras sanear equivale a no tenerlo: no es un error, el saludo usa el de macOS.
      config.greetingName = GreetingName.sanitize(value)
    }
    return .ok
  }

  private static func bool(_ value: String) -> Bool? {
    switch value {
    case "true": true
    case "false": false
    default: nil
    }
  }

  private static func isExecutableFile(_ path: String) -> Bool {
    guard path.hasPrefix("/") else { return false }
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
  }
}
