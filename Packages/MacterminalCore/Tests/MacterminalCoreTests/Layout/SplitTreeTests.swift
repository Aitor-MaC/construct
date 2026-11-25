import Testing

@testable import MacterminalCore

@Suite struct SplitTreeTests {
  @Test func singlePaneTreeListsOnlyItsRoot() {
    let root = PaneID()
    let tree = SplitTree(root: root)
    #expect(tree.paneIDs == [root])
    #expect(!tree.isEmpty)
  }

  @Test(arguments: [Axis.vertical, .horizontal])
  func insertPlacesNewPaneAfterTarget(_ axis: Axis) throws {
    let first = PaneID()
    let second = PaneID()
    var tree = SplitTree(root: first)
    try tree.insert(at: first, axis: axis, newID: second)
    #expect(tree.paneIDs == [first, second])
    #expect(tree.root == .split(axis, .leaf(first), .leaf(second)))
  }

  @Test func insertNestsInsideTheTargetedLeafOnly() throws {
    let a = PaneID()
    let b = PaneID()
    let c = PaneID()
    var tree = SplitTree(root: a)
    try tree.insert(at: a, axis: .vertical, newID: b)
    try tree.insert(at: a, axis: .horizontal, newID: c)
    #expect(tree.paneIDs == [a, c, b])
    #expect(tree.root == .split(.vertical, .split(.horizontal, .leaf(a), .leaf(c)), .leaf(b)))
  }

  @Test func insertRejectsDuplicateID() throws {
    let a = PaneID()
    let b = PaneID()
    var tree = SplitTree(root: a)
    try tree.insert(at: a, axis: .vertical, newID: b)
    #expect(throws: SplitTreeError.duplicatePane) {
      try tree.insert(at: b, axis: .horizontal, newID: a)
    }
    #expect(tree.paneIDs == [a, b])
  }

  @Test func insertRejectsUnknownTarget() {
    var tree = SplitTree(root: PaneID())
    let before = tree
    #expect(throws: SplitTreeError.paneNotFound) {
      try tree.insert(at: PaneID(), axis: .vertical, newID: PaneID())
    }
    #expect(tree == before)
  }

  @Test func removingOnlyPaneEmptiesTreeAndReturnsNil() {
    let root = PaneID()
    var tree = SplitTree(root: root)
    #expect(tree.remove(root) == nil)
    #expect(tree.isEmpty)
    #expect(tree.paneIDs.isEmpty)
  }

  @Test func emptyTreeHasNoPanesNeighborsOrInsertTarget() {
    let root = PaneID()
    var tree = SplitTree(root: root)
    _ = tree.remove(root)
    #expect(tree.neighbor(of: root, in: .right) == nil)
    #expect(tree.remove(root) == nil)
    #expect(throws: SplitTreeError.paneNotFound) {
      try tree.insert(at: root, axis: .vertical, newID: PaneID())
    }
  }

  @Test func removingLeafPromotesSiblingAndHandsItFocus() throws {
    let a = PaneID()
    let b = PaneID()
    var tree = SplitTree(root: a)
    try tree.insert(at: a, axis: .vertical, newID: b)
    #expect(tree.remove(b) == a)
    #expect(tree.root == .leaf(a))
  }

  @Test func removingLeafFocusesNearestLeafOfSiblingSubtree() throws {
    // [a | (b / c)]: removing a hands focus to b, the leaf touching a's edge first.
    let a = PaneID()
    let b = PaneID()
    let c = PaneID()
    var tree = SplitTree(root: a)
    try tree.insert(at: a, axis: .vertical, newID: b)
    try tree.insert(at: b, axis: .horizontal, newID: c)
    var afterFirst = tree
    #expect(afterFirst.remove(a) == b)
    #expect(afterFirst.root == .split(.horizontal, .leaf(b), .leaf(c)))
    // [(a / d) | b]: removing b hands focus to d, the last leaf of the left subtree.
    let d = PaneID()
    var other = SplitTree(root: a)
    try other.insert(at: a, axis: .vertical, newID: b)
    try other.insert(at: a, axis: .horizontal, newID: d)
    #expect(other.remove(b) == d)
  }

  @Test func removingUnknownPaneLeavesTreeUntouched() throws {
    let a = PaneID()
    var tree = SplitTree(root: a)
    try tree.insert(at: a, axis: .vertical, newID: PaneID())
    let before = tree
    #expect(tree.remove(PaneID()) == nil)
    #expect(tree == before)
  }

  /// Layout under test:
  /// ```
  /// +-------+-------+
  /// |       |   b   |
  /// |   a   +---+---+
  /// |       | c | d |
  /// +-------+---+---+
  /// ```
  private func nestedTree() throws -> (SplitTree, a: PaneID, b: PaneID, c: PaneID, d: PaneID) {
    let (a, b, c, d) = (PaneID(), PaneID(), PaneID(), PaneID())
    var tree = SplitTree(root: a)
    try tree.insert(at: a, axis: .vertical, newID: b)
    try tree.insert(at: b, axis: .horizontal, newID: c)
    try tree.insert(at: c, axis: .vertical, newID: d)
    return (tree, a, b, c, d)
  }

  @Test func neighborFollowsGeometryInAllFourDirections() throws {
    let (tree, a, b, c, d) = try nestedTree()
    #expect(tree.neighbor(of: c, in: .left) == a)
    #expect(tree.neighbor(of: c, in: .right) == d)
    #expect(tree.neighbor(of: c, in: .up) == b)
    #expect(tree.neighbor(of: b, in: .down) == c)
    #expect(tree.neighbor(of: d, in: .up) == b)
    #expect(tree.neighbor(of: d, in: .left) == c)
    #expect(tree.neighbor(of: b, in: .left) == a)
  }

  @Test func neighborPicksTheMostOverlappingPaneThenTheTopOrLeftOne() throws {
    let (tree, a, b, _, _) = try nestedTree()
    // b and c both touch a's right edge with equal overlap: the upper one wins.
    #expect(tree.neighbor(of: a, in: .right) == b)
  }

  @Test func neighborIsNilAtTheEdgesAndForUnknownPanes() throws {
    let (tree, a, b, _, d) = try nestedTree()
    #expect(tree.neighbor(of: a, in: .left) == nil)
    #expect(tree.neighbor(of: a, in: .up) == nil)
    #expect(tree.neighbor(of: a, in: .down) == nil)
    #expect(tree.neighbor(of: b, in: .up) == nil)
    #expect(tree.neighbor(of: d, in: .right) == nil)
    #expect(tree.neighbor(of: d, in: .down) == nil)
    #expect(tree.neighbor(of: PaneID(), in: .left) == nil)
  }

  @Test func paneIDsAreUniqueAcrossManyInsertions() throws {
    let root = PaneID()
    var tree = SplitTree(root: root)
    var target = root
    for index in 0..<16 {
      let next = PaneID()
      try tree.insert(at: target, axis: index.isMultiple(of: 2) ? .vertical : .horizontal, newID: next)
      target = next
    }
    #expect(tree.paneIDs.count == 17)
    #expect(Set(tree.paneIDs).count == 17)
  }
}
