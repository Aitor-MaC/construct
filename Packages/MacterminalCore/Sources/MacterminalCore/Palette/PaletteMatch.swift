/// Fila que pasa el filtro, con los rangos del título que coinciden con la búsqueda.
public struct PaletteMatch: Sendable, Identifiable {
  public let item: PaletteItem
  public let ranges: [Range<String.Index>]

  public var id: String { item.id }
}
