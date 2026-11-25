/// Binary tree of terminal panes. Divider positions belong to `NSSplitView`; geometry here is the
/// nominal 50/50 layout, which keeps directional focus predictable regardless of manual resizing.
public struct SplitTree: Sendable, Equatable {
  public indirect enum Node: Sendable, Equatable {
    case leaf(PaneID)
    /// `first` is the left or top pane, `second` the right or bottom one.
    case split(Axis, Node, Node)
  }

  public private(set) var root: Node?

  public init(root: PaneID) { self.root = .leaf(root) }

  public var isEmpty: Bool { root == nil }

  /// Panes in reading order: left to right, top to bottom.
  public var paneIDs: [PaneID] { root.map(Self.leaves) ?? [] }

  /// Splits `target`, placing `newID` to its right (`.vertical`) or below it (`.horizontal`).
  public mutating func insert(at target: PaneID, axis: Axis, newID: PaneID) throws(SplitTreeError) {
    let existing = paneIDs
    guard let root, existing.contains(target) else { throw .paneNotFound }
    guard !existing.contains(newID) else { throw .duplicatePane }
    self.root = Self.replacing(target, in: root, with: .split(axis, .leaf(target), .leaf(newID)))
  }

  /// Removes `id` and returns the pane that should receive focus: the leaf of the promoted
  /// sibling that touches the removed pane's edge. `nil` when the tree empties or `id` is unknown.
  public mutating func remove(_ id: PaneID) -> PaneID? {
    guard let root else { return nil }
    if root == .leaf(id) {
      self.root = nil
      return nil
    }
    guard let (newRoot, heir) = Self.removing(id, from: root) else { return nil }
    self.root = newRoot
    return heir
  }

  /// The pane geometrically adjacent to `id` in `direction`; ties go to the longest shared edge,
  /// then to the topmost or leftmost pane.
  public func neighbor(of id: PaneID, in direction: Direction) -> PaneID? {
    guard let root else { return nil }
    var frames: [PaneFrame] = []
    Self.layout(root, in: UnitRect(minX: 0, minY: 0, maxX: 1, maxY: 1), into: &frames)
    guard let source = frames.first(where: { $0.id == id })?.rect else { return nil }
    let candidates = frames.compactMap { frame -> (id: PaneID, overlap: Double, start: Double)? in
      guard let overlap = source.sharedEdge(with: frame.rect, toward: direction) else { return nil }
      let isHorizontalMove = direction == .left || direction == .right
      return (frame.id, overlap, isHorizontalMove ? frame.rect.minY : frame.rect.minX)
    }
    return candidates.min { lhs, rhs in
      lhs.overlap != rhs.overlap ? lhs.overlap > rhs.overlap : lhs.start < rhs.start
    }?.id
  }

  private static func leaves(of node: Node) -> [PaneID] {
    switch node {
    case .leaf(let id): [id]
    case .split(_, let first, let second): leaves(of: first) + leaves(of: second)
    }
  }

  private static func replacing(_ target: PaneID, in node: Node, with replacement: Node) -> Node {
    switch node {
    case .leaf(let id): id == target ? replacement : node
    case .split(let axis, let first, let second):
      .split(
        axis, replacing(target, in: first, with: replacement),
        replacing(target, in: second, with: replacement))
    }
  }

  private static func removing(_ id: PaneID, from node: Node) -> (Node, PaneID)? {
    guard case .split(let axis, let first, let second) = node else { return nil }
    // The heir is the sibling leaf nearest the removed pane's edge.
    if first == .leaf(id), let heir = leaves(of: second).first { return (second, heir) }
    if second == .leaf(id), let heir = leaves(of: first).last { return (first, heir) }
    if let (newFirst, heir) = removing(id, from: first) {
      return (.split(axis, newFirst, second), heir)
    }
    if let (newSecond, heir) = removing(id, from: second) {
      return (.split(axis, first, newSecond), heir)
    }
    return nil
  }

  private static func layout(_ node: Node, in rect: UnitRect, into frames: inout [PaneFrame]) {
    switch node {
    case .leaf(let id): frames.append(PaneFrame(id: id, rect: rect))
    case .split(let axis, let first, let second):
      let (firstRect, secondRect) = rect.halves(along: axis)
      layout(first, in: firstRect, into: &frames)
      layout(second, in: secondRect, into: &frames)
    }
  }
}

private struct PaneFrame {
  let id: PaneID
  let rect: UnitRect
}

/// Rectangle in the unit square, y growing downwards. Halving binary fractions is exact in
/// `Double`, so edges can be compared with `==`.
private struct UnitRect: Equatable {
  var minX, minY, maxX, maxY: Double

  func halves(along axis: Axis) -> (UnitRect, UnitRect) {
    switch axis {
    case .vertical:
      let mid = (minX + maxX) / 2
      return (
        UnitRect(minX: minX, minY: minY, maxX: mid, maxY: maxY),
        UnitRect(minX: mid, minY: minY, maxX: maxX, maxY: maxY)
      )
    case .horizontal:
      let mid = (minY + maxY) / 2
      return (
        UnitRect(minX: minX, minY: minY, maxX: maxX, maxY: mid),
        UnitRect(minX: minX, minY: mid, maxX: maxX, maxY: maxY)
      )
    }
  }

  /// Length of the edge shared with `other` when `other` lies directly toward `direction`.
  func sharedEdge(with other: UnitRect, toward direction: Direction) -> Double? {
    let touches: Bool
    let overlap: Double
    switch direction {
    case .left, .right:
      touches = direction == .left ? other.maxX == minX : other.minX == maxX
      overlap = min(maxY, other.maxY) - max(minY, other.minY)
    case .up, .down:
      touches = direction == .up ? other.maxY == minY : other.minY == maxY
      overlap = min(maxX, other.maxX) - max(minX, other.minX)
    }
    return touches && overlap > 0 ? overlap : nil
  }
}
