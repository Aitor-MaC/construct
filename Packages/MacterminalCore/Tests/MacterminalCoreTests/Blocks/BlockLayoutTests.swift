import Foundation
import Testing

@testable import MacterminalCore

@MainActor @Suite struct BlockLayoutTests {
  /// Tres comandos de 3 filas (prompt, comando, salida) y el prompt actual en la fila 9.
  private func threeCommands() -> TrackerHarness {
    let harness = TrackerHarness()
    harness.runCommand("ls", row: 0)
    harness.runCommand("swift build", exit: "1", row: 3)
    harness.runCommand("git status", row: 6)
    harness.feed("A", row: 9)
    return harness
  }

  @Test func finishedBlocksSpanFromTheirPromptToTheNextOneAndTheEditingPromptIsNotDrawn() {
    let harness = threeCommands()
    let frames = BlockLayout.frames(
      of: harness.tracker.blocks, visibleRows: 0..<20, contentEnd: 11, resolve: harness.resolve)
    #expect(frames.map(\.rows) == [0..<3, 3..<6, 6..<9])
    #expect(frames.map(\.id) == harness.tracker.blocks.prefix(3).map(\.id))
    #expect(frames.map(\.showsHeader) == [true, true, true])
  }

  @Test func framesAreClippedToTheVisibleRows() {
    let harness = threeCommands()
    let frames = BlockLayout.frames(
      of: harness.tracker.blocks, visibleRows: 4..<8, contentEnd: 11, resolve: harness.resolve)
    #expect(frames.map(\.rows) == [4..<6, 6..<8])
    #expect(frames.map(\.showsHeader) == [false, true])
  }

  @Test func blocksWhoseAnchorsNoLongerResolveAreNotDrawn() {
    let harness = threeCommands()
    // Recorte de scrollback: el prompt del primer bloque ya no está en el buffer.
    harness.rows[harness.tracker.blocks[0].promptAnchor] = nil
    let frames = BlockLayout.frames(
      of: harness.tracker.blocks, visibleRows: 0..<20, contentEnd: 11, resolve: harness.resolve)
    #expect(frames.map(\.rows) == [3..<6, 6..<9])
  }

  @Test func afterClearNoBlockIsDrawnEvenIfStaleAnchorsWouldPointOutOfRange() {
    let harness = threeCommands()
    // ⌘K: el buffer queda vacío (ninguna ancla resuelve) y el tracker se reinicia después.
    harness.rows = [:]
    #expect(
      BlockLayout.frames(
        of: harness.tracker.blocks, visibleRows: 0..<20, contentEnd: 1, resolve: harness.resolve
      ).isEmpty)
    harness.tracker.reset()
    #expect(
      BlockLayout.frames(
        of: harness.tracker.blocks, visibleRows: 0..<20, contentEnd: 1, resolve: harness.resolve
      ).isEmpty)
  }

  @Test func aRunningLastBlockReachesTheEndOfTheContent() {
    let harness = TrackerHarness()
    harness.runCommand("ls", row: 0)
    harness.feed("A", row: 3)
    harness.feed("B", row: 3)
    harness.feed("C", ProtocolFixture.base64("make"), row: 4)
    let frames = BlockLayout.frames(
      of: harness.tracker.blocks, visibleRows: 0..<20, contentEnd: 12, resolve: harness.resolve)
    #expect(frames.map(\.rows) == [0..<3, 3..<12])
  }

  @Test func aBlockWithAPromptAfterTheNextOneIsSkippedInsteadOfOverlapping() {
    let harness = threeCommands()
    // Reflow incoherente: el segundo prompt resuelve por debajo del tercero.
    harness.rows[harness.tracker.blocks[1].promptAnchor] = 7
    let frames = BlockLayout.frames(
      of: harness.tracker.blocks, visibleRows: 0..<20, contentEnd: 11, resolve: harness.resolve)
    #expect(frames.map(\.rows) == [0..<6, 6..<9])
  }

  @Test func withFiveThousandBlocksOnlyTheVisibleOnesAreLaidOut() {
    let harness = TrackerHarness()
    for index in 0..<BlockTracker.maxBlocks {
      harness.runCommand("echo \(index)", row: index * 3)
    }
    let last = BlockTracker.maxBlocks * 3
    harness.feed("A", row: last)
    let frames = BlockLayout.frames(
      of: harness.tracker.blocks, visibleRows: (last - 30)..<(last + 1), contentEnd: last + 2,
      resolve: harness.resolve)
    #expect(frames.count == 10)
    #expect(frames.first?.rows == (last - 30)..<(last - 27))
  }
}
