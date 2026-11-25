import Foundation

public struct PaletteItem: Sendable, Hashable, Identifiable {
  public let group: PaletteGroup
  public let title: String
  public let shortcut: KeyShortcut?
  public let run: PaletteResult
  /// Última vez que se usó; solo el historial lo conoce (en el resto, `nil`).
  public let lastUsed: Date?

  public init(
    group: PaletteGroup, title: String, shortcut: KeyShortcut? = nil, run: PaletteResult,
    lastUsed: Date? = nil
  ) {
    self.group = group
    self.title = title
    self.shortcut = shortcut
    self.run = run
    self.lastUsed = lastUsed
  }

  /// Dentro de un grupo el título no se repite: el historial y las carpetas ya llegan sin duplicados.
  public var id: String { "\(group.rawValue):\(title)" }
}
