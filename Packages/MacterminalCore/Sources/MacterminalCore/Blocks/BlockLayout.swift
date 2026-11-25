import Foundation

/// Filas que ocupa un bloque dentro de la vista. `rows` son filas absolutas del buffer ya
/// recortadas a lo visible.
public struct BlockFrame: Sendable, Equatable, Identifiable {
  public let id: UUID
  public let rows: Range<Int>
  /// La fila del prompt (la cabecera del bloque) está dentro de la vista.
  public let showsHeader: Bool
}

public enum BlockLayout {
  /// Un bloque va de su prompt al prompt siguiente; el último en marcha llega hasta
  /// `contentEnd` (fila tras el cursor). El prompt en edición marca el límite pero no se dibuja.
  /// Un bloque sin ancla resoluble, o con el prompt por debajo del siguiente (reflow incoherente),
  /// no se dibuja. Se recorre desde el final y se para al salir por arriba de la vista: con miles
  /// de bloques solo se resuelven los cercanos a lo visible.
  public static func frames(
    of blocks: [CommandBlock], visibleRows: Range<Int>, contentEnd: Int,
    resolve: (RowAnchor) -> Int?
  ) -> [BlockFrame] {
    var frames: [BlockFrame] = []
    var nextStart: Int?
    for block in blocks.reversed() {
      guard let start = resolve(block.promptAnchor) else { continue }
      if let nextStart, start >= nextStart { continue }
      let end = nextStart ?? max(contentEnd, start + 1)
      nextStart = start
      if end <= visibleRows.lowerBound { break }
      let visible = start..<end
      guard block.state != .editing, visible.overlaps(visibleRows) else { continue }
      frames.append(
        BlockFrame(
          id: block.id, rows: visible.clamped(to: visibleRows),
          showsHeader: visibleRows.contains(start)))
    }
    return frames.reversed()
  }
}
