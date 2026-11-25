import Foundation

/// Construye las filas de la paleta a partir del catálogo de acciones y del historial.
public enum PaletteCatalog {
  /// Las intensidades van a Ajustes; el resto, a Acciones. Abrir la paleta desde ella no tiene sentido.
  public static func actionItems(from catalog: [TerminalAction]) -> [PaletteItem] {
    catalog.compactMap { action in
      switch action {
      case .commandPalette: nil
      case .setIntensity:
        PaletteItem(group: .settings, title: action.title, run: .action(action))
      default:
        PaletteItem(
          group: .actions, title: action.title, shortcut: action.shortcut, run: .action(action))
      }
    }
  }

  public static func historyItems(commands: [HistoryEntry], directories: [URL], home: URL)
    -> [PaletteItem]
  {
    let history = commands.map {
      PaletteItem(group: .history, title: $0.command, run: .insert($0.command), lastUsed: $0.lastUsed)
    }
    let folders = directories.map {
      PaletteItem(
        group: .folders, title: displayPath(of: $0, home: home),
        run: .insert(ShellLiteral.changeDirectory(to: $0)))
    }
    return history + folders
  }

  /// Ruta para leer, con `~` para la carpeta personal. Solo se muestra; el `cd` usa la ruta completa.
  public static func displayPath(of url: URL, home: URL) -> String {
    let path = trimmingTrailingSlash(url.path(percentEncoded: false))
    let homePath = trimmingTrailingSlash(home.path(percentEncoded: false))
    if path == homePath { return "~" }
    if path.hasPrefix(homePath + "/") { return "~" + path.dropFirst(homePath.count) }
    return path
  }

  private static func trimmingTrailingSlash(_ path: String) -> String {
    path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
  }
}
