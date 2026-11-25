import Foundation

public struct ViewportSnapshot: Sendable {
  public let topRow: Int
  public let rows: Int
  public let columns: Int
  public let cellSize: CGSize
  public let occupiedRows: IndexSet
  public let cursor: GridPosition?
  public init(
    topRow: Int, rows: Int, columns: Int, cellSize: CGSize, occupiedRows: IndexSet,
    cursor: GridPosition?
  ) {
    self.topRow = topRow
    self.rows = rows
    self.columns = columns
    self.cellSize = cellSize
    self.occupiedRows = occupiedRows
    self.cursor = cursor
  }
  private func viewportRow(_ row: Int) -> Int? {
    let (relative, overflow) = row.subtractingReportingOverflow(topRow)
    return !overflow && relative >= 0 && relative < rows ? relative : nil
  }
  public func viewportOccupiedRows() -> IndexSet { IndexSet(occupiedRows.compactMap(viewportRow)) }
  public func viewportCursor() -> GridPosition? {
    guard let cursor, cursor.col >= 0, cursor.col < columns, let row = viewportRow(cursor.row)
    else { return nil }
    return GridPosition(col: cursor.col, row: row)
  }
}
