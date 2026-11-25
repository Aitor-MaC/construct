import Foundation

extension KeyShortcut {
  /// Forma de `quake-hotkey` en el archivo (`ctrl+grave`); `init(configString:)` la vuelve a leer.
  public var configString: String {
    let order: [Modifier] = [.ctrl, .alt, .shift, .cmd]
    return (order.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "+")
  }
}

/// Resultado de comprobar un atajo Quake grabado en Ajustes.
public enum QuakeHotkeyCheck: Sendable, Equatable {
  case valid
  /// Sin ⌘, ⌃ ni ⌥: un atajo global así se dispararía al escribir.
  case missingModifier
  /// Ya lo usa una acción del menú de la app.
  case conflict(TerminalAction)
}

/// Resultado de comprobar la ruta del shell escrita en Ajustes.
public enum ShellPathCheck: Sendable, Equatable {
  /// Valor que se escribe en `shell`.
  case valid(String)
  case notExecutable
}

/// Validación de la entrada de la ventana de Ajustes antes de llamar a `ConfigStore.set`.
public enum SettingsInput {
  public static func checkQuakeHotkey(_ shortcut: KeyShortcut) -> QuakeHotkeyCheck {
    guard !shortcut.modifiers.isDisjoint(with: [.cmd, .ctrl, .alt]) else { return .missingModifier }
    let owner = TerminalAction.catalog.first { $0 != .toggleQuake && $0.shortcut == shortcut }
    return owner.map(QuakeHotkeyCheck.conflict) ?? .valid
  }

  /// Ruta vacía = `$SHELL`: nunca se escribe una cadena vacía. Usa la misma regla que el parser.
  public static func checkShellPath(
    _ typed: String, defaultShell: String = TerminalConfig.defaults.shell
  ) -> ShellPathCheck {
    let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    let path = trimmed.isEmpty ? defaultShell : trimmed
    var probe = TerminalConfig(shell: path)
    guard case .ok = ConfigParser.apply(.shell, path, to: &probe) else { return .notExecutable }
    return .valid(path)
  }
}
