public struct GridPosition: Sendable, Hashable {
  public var col: Int
  public var row: Int
  public init(col: Int, row: Int) {
    self.col = col
    self.row = row
  }
}
