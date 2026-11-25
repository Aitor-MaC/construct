/// Filas publicadas para una consulta y la fila seleccionada: lo que ⏎ ejecuta.
public struct PaletteListing: Sendable {
  public let query: String
  public let matches: [PaletteMatch]
  public private(set) var selection: Int?

  /// Empieza en la fila elegida antes (`keeping`) si sigue en la lista; si no, en la primera que
  /// se puede ejecutar ahora, para que ⏎ justo después de teclear haga algo.
  public init(
    query: String, matches: [PaletteMatch], keeping selectedID: PaletteItem.ID? = nil,
    isEnabled: (PaletteItem) -> Bool
  ) {
    self.query = query
    self.matches = matches
    let kept = selectedID.flatMap { id in matches.firstIndex { $0.id == id } }
    let firstEnabled = matches.firstIndex { isEnabled($0.item) }
    selection = kept ?? firstEnabled ?? (matches.isEmpty ? nil : 0)
  }

  public var selectedItem: PaletteItem? {
    selection.map { matches[$0].item }
  }

  /// El filtrado normal va fuera del hilo principal y puede no haberse publicado cuando llega ⏎:
  /// entonces se filtra aquí, en síncrono, para no ejecutar una fila de la consulta anterior.
  public func refreshed(
    for currentQuery: String, items: [PaletteItem], isEnabled: (PaletteItem) -> Bool
  ) -> PaletteListing {
    guard currentQuery != query else { return self }
    return PaletteListing(
      query: currentQuery, matches: PaletteSearch.filter(items, query: currentQuery),
      isEnabled: isEnabled)
  }

  public mutating func moveSelection(by delta: Int) {
    selection = PaletteSelection.moved(selection ?? 0, by: delta, count: matches.count)
  }

  /// `false` si el índice ya no existe (la lista cambió debajo del puntero).
  @discardableResult public mutating func select(_ index: Int) -> Bool {
    guard matches.indices.contains(index) else { return false }
    selection = index
    return true
  }
}
