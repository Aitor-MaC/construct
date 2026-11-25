/// Una fila visible: su posición en la lista plana (para ↑↓) y la coincidencia que muestra.
public struct PaletteRowEntry: Sendable, Identifiable {
  public let index: Int
  public let match: PaletteMatch
  public var id: String { match.id }
}

/// Filas contiguas bajo una misma cabecera de grupo.
public struct PaletteSection: Sendable, Identifiable {
  public let group: PaletteGroup
  public let rows: [PaletteRowEntry]
  public var id: PaletteGroup { group }

  /// Espera las coincidencias ya ordenadas por grupo, como las deja `PaletteSearch.filter`.
  public static func sections(of matches: [PaletteMatch]) -> [PaletteSection] {
    var result: [PaletteSection] = []
    var current: [PaletteRowEntry] = []
    for (index, match) in matches.enumerated() {
      if let last = current.last, last.match.item.group != match.item.group {
        result.append(PaletteSection(group: last.match.item.group, rows: current))
        current = []
      }
      current.append(PaletteRowEntry(index: index, match: match))
    }
    if let last = current.last {
      result.append(PaletteSection(group: last.match.item.group, rows: current))
    }
    return result
  }
}
