import CoreGraphics
import MacterminalCore

/// Filas absolutas → puntos de la vista. La capa de bloques ocupa exactamente la rejilla de la
/// terminal, así que la fila `viewport.topRow` empieza en y = 0.
struct BlockGeometry {
  let viewport: ViewportSnapshot

  var visibleRows: Range<Int> {
    let (end, overflow) = viewport.topRow.addingReportingOverflow(max(viewport.rows, 0))
    return viewport.topRow..<(overflow ? Int.max : end)
  }

  var cellHeight: CGFloat { viewport.cellSize.height }

  func top(of row: Int) -> CGFloat { CGFloat(row - viewport.topRow) * cellHeight }

  func height(of rows: Range<Int>) -> CGFloat { CGFloat(rows.count) * cellHeight }

  /// Fila absoluta bajo un punto, o `nil` fuera de la rejilla.
  func row(at y: CGFloat) -> Int? {
    guard cellHeight > 0, y >= 0, y.isFinite else { return nil }
    let row = viewport.topRow + Int(y / cellHeight)
    return visibleRows.contains(row) ? row : nil
  }

  @MainActor func frames(of tracker: BlockTracker, resolve: (RowAnchor) -> Int?) -> [BlockFrame] {
    let visible = visibleRows
    // Sin cursor conocido, el último bloque en marcha llega hasta el final de la vista.
    let contentEnd = viewport.cursor.map { $0.row + 1 } ?? visible.upperBound
    return BlockLayout.frames(
      of: tracker.blocks, visibleRows: visible, contentEnd: contentEnd, resolve: resolve)
  }
}
