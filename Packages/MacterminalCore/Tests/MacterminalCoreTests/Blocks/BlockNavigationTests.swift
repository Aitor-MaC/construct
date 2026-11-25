import Foundation
import Testing

@testable import MacterminalCore

@MainActor @Suite struct BlockNavigationTests {
  /// Bloques en las filas 0, 3 y 6; el prompt actual (editing) en la 9; la vista acaba en la 30.
  private func threeCommands() -> TrackerHarness {
    let harness = TrackerHarness()
    harness.runCommand("ls", row: 0)
    harness.runCommand("swift build", row: 3)
    harness.runCommand("git status", row: 6)
    harness.feed("A", row: 9)
    return harness
  }

  private func step(
    _ step: BlockStep, from selected: UUID?, _ harness: TrackerHarness
  ) -> BlockTarget? {
    BlockNavigation.target(
      step, from: selected, in: harness.tracker, viewportBottom: 30, resolve: harness.resolve)
  }

  @Test func previousWithoutSelectionPicksTheLastCommandAndSkipsTheCurrentPrompt() {
    let harness = threeCommands()
    let blocks = harness.tracker.blocks
    #expect(step(.previous, from: nil, harness) == BlockTarget(id: blocks[2].id, row: 6))
  }

  @Test func previousAndNextMoveOneBlockFromTheSelection() {
    let harness = threeCommands()
    let blocks = harness.tracker.blocks
    #expect(step(.previous, from: blocks[1].id, harness) == BlockTarget(id: blocks[0].id, row: 0))
    #expect(step(.next, from: blocks[1].id, harness) == BlockTarget(id: blocks[2].id, row: 6))
  }

  @Test func atTheEdgesThereIsNoTarget() {
    let harness = threeCommands()
    let blocks = harness.tracker.blocks
    #expect(step(.previous, from: blocks[0].id, harness) == nil)
    // El siguiente del último comando es el prompt en edición, que no es un bloque navegable.
    #expect(step(.next, from: blocks[2].id, harness) == nil)
    #expect(step(.next, from: nil, harness) == nil)
  }

  @Test func aSelectionThatNoLongerExistsBehavesAsNoSelection() {
    let harness = threeCommands()
    let gone = harness.tracker.blocks[0].id
    harness.rows[harness.tracker.blocks[0].promptAnchor] = nil
    harness.tracker.prune(resolve: harness.resolve)
    #expect(step(.previous, from: gone, harness)?.row == 6)
  }

  @Test func withoutSelectionPreviousStartsFromTheBottomOfTheView() {
    let harness = threeCommands()
    let blocks = harness.tracker.blocks
    let target = BlockNavigation.target(
      .previous, from: nil, in: harness.tracker, viewportBottom: 5, resolve: harness.resolve)
    #expect(target == BlockTarget(id: blocks[1].id, row: 3))
  }
}
