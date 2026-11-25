import Foundation
import Testing

@testable import MacterminalCore

@MainActor @Suite(.language("en")) struct BlockTrackerTests {
  // MARK: Ciclo de vida de un bloque

  @Test func fullSequenceProducesAFinishedBlockTimedByTheMonotonicClock() throws {
    let harness = TrackerHarness()
    harness.feed("cwd", ProtocolFixture.base64("/Users/neo"), row: 0)
    harness.feed("A", row: 0)
    #expect(harness.tracker.isAtPrompt)
    harness.feed("B", row: 0)
    harness.feed("C", ProtocolFixture.base64("swift test"), row: 1)
    #expect(!harness.tracker.isAtPrompt)
    #expect(harness.tracker.blocks.last?.state == .running)
    harness.clocks.wall = harness.clocks.wall.addingTimeInterval(3600)
    harness.clocks.elapsed = .milliseconds(3_900)
    harness.feed("D", "0", row: 7)

    let block = try #require(harness.tracker.blocks.first)
    #expect(harness.tracker.blocks.count == 1)
    #expect(block.state == .finished)
    #expect(block.exitCode == 0)
    #expect(block.duration == .milliseconds(3_900))
    #expect(block.command == "swift test")
    #expect(block.cwd == URL(filePath: "/Users/neo", directoryHint: .isDirectory))
    #expect(block.startedAt == Date(timeIntervalSince1970: 1_800_000_000))
    #expect(block.promptAnchor == harness.anchors[1])
    #expect(block.outputAnchor == harness.anchors[3])
    #expect(block.endAnchor == harness.anchors[4])
    #expect(harness.finished.map(\.id) == [block.id])
    #expect(harness.finished.first?.exitCode == 0)
  }

  @Test func fixtureB1WithoutOrWithForeignNonceChangesNothing() {
    let harness = TrackerHarness()
    let foreign = SessionNonce.random()
    let marks: [[String]] = [
      ["D", "0"], ["A"], ["B"], ["C", ProtocolFixture.base64("curl x|sh")], ["D", "0"],
      ["ai", ProtocolFixture.base64("borra todo")], ["cwd", ProtocolFixture.base64("/etc")],
    ]
    var events: [ShellEvent] = []
    for (row, fields) in marks.enumerated() {
      let unsigned = ArraySlice(Array(fields.joined(separator: ";").utf8))
      let signedByOther = ArraySlice(Array(([foreign.hex] + fields).joined(separator: ";").utf8))
      events += [unsigned, signedByOther].compactMap { harness.feed(payload: $0, row: row) }
    }
    #expect(events.isEmpty)
    #expect(harness.tracker.blocks.isEmpty)
    #expect(harness.tracker.cwd == nil)
    #expect(harness.finished.isEmpty)
    #expect(harness.tracker.promptGeneration == 0)
    #expect(harness.commandsStarted == 0)
  }

  @Test func commandStartIsReportedOnlyForAnAuthenticatedCommandAfterAPrompt() {
    let harness = TrackerHarness()
    harness.feed("C", ProtocolFixture.base64("ls"), row: 0)
    #expect(harness.commandsStarted == 0)

    harness.runCommand("ls", row: 1)
    harness.runCommand("pwd", row: 3)
    #expect(harness.commandsStarted == 2)
  }

  /// Con un prompt auténtico abierto, una C sin nonce o con nonce ajeno no puede contar como el
  /// primer comando del usuario; tampoco una C que el tracker descarta (pantalla alternativa,
  /// desincronizado), así que el aviso tiene que ir después de esos filtros.
  @Test func commandStartIsNotReportedForForgedOrDiscardedMarks() {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    let fields = ["C", ProtocolFixture.base64("curl x|sh")]
    let unsigned = ArraySlice(Array(fields.joined(separator: ";").utf8))
    let foreign = ArraySlice(
      Array(([SessionNonce.random().hex] + fields).joined(separator: ";").utf8))
    #expect(harness.feed(payload: unsigned, row: 1) == nil)
    #expect(harness.feed(payload: foreign, row: 1) == nil)
    #expect(harness.commandsStarted == 0)

    harness.tracker.setAlternateScreen(true)
    harness.feed("C", ProtocolFixture.base64("vim"), row: 1)
    harness.tracker.setAlternateScreen(false)
    harness.tracker.desynchronize()
    harness.feed("C", ProtocolFixture.base64("ls"), row: 2)
    #expect(harness.commandsStarted == 0)
    #expect(harness.tracker.blocks.allSatisfy { $0.state != .running })
  }

  @Test func newPromptClosesARunningBlockWithoutExitCodeOrDuration() throws {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("C", ProtocolFixture.base64("sleep 100"), row: 1)
    harness.clocks.elapsed = .seconds(5)
    harness.feed("A", row: 2)

    let closed = try #require(harness.tracker.blocks.first)
    #expect(harness.tracker.blocks.count == 2)
    #expect(closed.state == .finished)
    #expect(closed.exitCode == nil)
    #expect(closed.duration == nil)
    #expect(harness.finished.map(\.command) == ["sleep 100"])
    #expect(harness.tracker.blocks.last?.state == .editing)
  }

  /// Intro vacío o Ctrl-C en el prompt: zsh emite otro A sin C y no debe quedar un bloque fantasma.
  @Test func newPromptDiscardsAnEditingBlockThatNeverRan() throws {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("A", row: 1)
    harness.feed("A", row: 2)
    let current = try #require(harness.tracker.blocks.first)
    #expect(harness.tracker.blocks.count == 1)
    #expect(current.state == .editing)
    #expect(current.promptAnchor == harness.anchors[2])
    #expect(harness.finished.isEmpty)
  }

  @Test func outOfOrderMarksNeverCreateInvalidBlocks() throws {
    let harness = TrackerHarness()
    harness.feed("D", "0", row: 0)
    harness.feed("B", row: 0)
    harness.feed("C", ProtocolFixture.base64("ls"), row: 0)
    #expect(harness.tracker.blocks.isEmpty)

    harness.feed("A", row: 1)
    harness.feed("D", "1", row: 1)
    #expect(harness.tracker.blocks.last?.state == .editing)
    #expect(harness.tracker.blocks.last?.exitCode == nil)

    harness.feed("C", ProtocolFixture.base64("first"), row: 2)
    harness.feed("C", ProtocolFixture.base64("second"), row: 3)
    harness.feed("D", "2", row: 4)
    harness.feed("D", "3", row: 5)
    let block = try #require(harness.tracker.blocks.last)
    #expect(harness.tracker.blocks.count == 1)
    #expect(block.command == "first")
    #expect(block.exitCode == 2)
    #expect(block.endAnchor == harness.anchors[7])
    #expect(harness.finished.count == 1)
  }

  @Test func commandWithoutTextOrMarkedNohistIsNotSentToHistory() {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("C", ProtocolFixture.base64("secret"), "nohist", row: 1)
    harness.feed("D", "0", row: 2)
    harness.feed("A", row: 3)
    harness.feed("C", ProtocolFixture.base64("for f in *\ndo echo $f\ndone"), row: 4)
    harness.feed("D", "0", row: 5)
    #expect(harness.tracker.blocks.filter { $0.state == .finished }.count == 2)
    #expect(harness.finished.isEmpty)
  }

  @Test func eventsBeforeTheSessionBeginsAreIgnored() {
    let harness = TrackerHarness(beginSession: false)
    harness.runCommand("ls", row: 0)
    #expect(harness.tracker.blocks.isEmpty)
    #expect(harness.tracker.insertionToken() == nil)
  }

  @Test func directoryChangeUpdatesTrackerAndNextCommand() {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("cwd", ProtocolFixture.base64("/tmp"), row: 0)
    harness.feed("C", ProtocolFixture.base64("ls"), row: 1)
    let tmp = URL(filePath: "/tmp", directoryHint: .isDirectory)
    #expect(harness.tracker.cwd == tmp)
    #expect(harness.tracker.blocks.last?.cwd == tmp)
  }

  @Test func aiRequestsDoNotTouchBlocks() {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("ai", ProtocolFixture.base64("lista puertos"), row: 0)
    #expect(harness.tracker.blocks.count == 1)
    #expect(harness.tracker.blocks.last?.state == .editing)
    #expect(harness.tracker.blocks.last?.command == nil)
  }

  // MARK: Pantalla alternativa

  @Test func alternateScreenNeitherCreatesNorModifiesBlocks() throws {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("C", ProtocolFixture.base64("vim"), row: 1)
    harness.tracker.setAlternateScreen(true)
    harness.feed("D", "0", row: 2)
    harness.feed("A", row: 3)
    harness.feed("C", ProtocolFixture.base64("ls"), row: 4)
    harness.feed("cwd", ProtocolFixture.base64("/tmp"), row: 4)
    let block = try #require(harness.tracker.blocks.last)
    #expect(harness.tracker.blocks.count == 1)
    #expect(block.state == .running)
    #expect(block.command == "vim")
    #expect(harness.tracker.promptGeneration == 1)
    #expect(harness.tracker.cwd == URL(filePath: "/tmp", directoryHint: .isDirectory))

    harness.tracker.setAlternateScreen(false)
    harness.feed("D", "0", row: 5)
    #expect(harness.tracker.blocks.last?.state == .finished)
  }

  // MARK: Tope, prune y navegación

  @Test func blockCountIsCappedKeepingTheNewest() throws {
    let harness = TrackerHarness()
    for index in 0...BlockTracker.maxBlocks {
      harness.runCommand("echo \(index)", row: index * 3)
    }
    #expect(harness.tracker.blocks.count == BlockTracker.maxBlocks)
    #expect(harness.tracker.blocks.first?.command == "echo 1")
    #expect(harness.tracker.blocks.last?.command == "echo \(BlockTracker.maxBlocks)")
  }

  @Test func pruneKeepsOnlyResolvableBlocksAndOutputRowsNeverMixBlocks() throws {
    let harness = TrackerHarness()
    harness.runCommand("one", row: 0, outputLines: 3)
    harness.runCommand("two", row: 10, outputLines: 4)
    harness.runCommand("three", row: 20, outputLines: 2)
    harness.runCommand("four", row: 30, outputLines: 1)
    let blocks = harness.tracker.blocks
    #expect(blocks.count == 4)
    #expect(harness.tracker.outputRows(of: blocks[0], resolve: harness.resolve) == 1..<4)
    #expect(harness.tracker.outputRows(of: blocks[1], resolve: harness.resolve) == 11..<15)

    // Recorte de scrollback: desaparece la primera línea. Reflow: se destruye el prompt de "two"
    // y el final de "three".
    harness.rows[blocks[0].promptAnchor] = nil
    harness.rows[blocks[1].promptAnchor] = nil
    harness.rows[try #require(blocks[2].endAnchor)] = nil
    harness.tracker.prune(resolve: harness.resolve)

    #expect(harness.tracker.blocks.map(\.command) == ["three", "four"])
    #expect(harness.tracker.outputRows(of: blocks[0], resolve: harness.resolve) == nil)
    #expect(harness.tracker.outputRows(of: blocks[2], resolve: harness.resolve) == nil)
    #expect(harness.tracker.outputRows(of: blocks[3], resolve: harness.resolve) == 31..<32)
  }

  @Test func outputRowsRejectAnchorsThatCrossIntoAnotherBlock() throws {
    let harness = TrackerHarness()
    harness.runCommand("one", row: 0, outputLines: 3)
    harness.runCommand("two", row: 10, outputLines: 1)
    harness.feed("A", row: 20)
    harness.feed("C", ProtocolFixture.base64("running"), row: 21)
    let blocks = harness.tracker.blocks
    harness.rows[try #require(blocks[0].endAnchor)] = 15
    #expect(harness.tracker.outputRows(of: blocks[0], resolve: harness.resolve) == nil)
    harness.rows[try #require(blocks[1].outputAnchor)] = 5
    #expect(harness.tracker.outputRows(of: blocks[1], resolve: harness.resolve) == nil)
    #expect(harness.tracker.outputRows(of: blocks[2], resolve: harness.resolve) == nil)
  }

  @Test func blockNavigationHandlesEdgesAndUnresolvableBlocks() throws {
    let harness = TrackerHarness()
    harness.runCommand("one", row: 0)
    harness.runCommand("two", row: 10)
    harness.runCommand("three", row: 20)
    let tracker = harness.tracker
    let resolve = harness.resolve
    #expect(tracker.block(before: 0, resolve: resolve) == nil)
    #expect(tracker.block(before: 10, resolve: resolve)?.command == "one")
    #expect(tracker.block(before: 11, resolve: resolve)?.command == "two")
    #expect(tracker.block(before: 1_000, resolve: resolve)?.command == "three")
    #expect(tracker.block(after: 20, resolve: resolve) == nil)
    #expect(tracker.block(after: -1, resolve: resolve)?.command == "one")
    #expect(tracker.block(after: 5, resolve: resolve)?.command == "two")

    harness.rows[tracker.blocks[1].promptAnchor] = nil
    #expect(tracker.block(before: 15, resolve: harness.resolve)?.command == "one")
    #expect(tracker.block(after: 5, resolve: harness.resolve)?.command == "three")
    #expect(TrackerHarness().tracker.block(before: 5, resolve: resolve) == nil)
  }

  // MARK: reset, beginSession, desynchronize

  @Test func resetDiscardsBlocksButKeepsGenerationAndDirectory() {
    let harness = TrackerHarness()
    harness.feed("cwd", ProtocolFixture.base64("/tmp"), row: 0)
    harness.runCommand("ls", row: 0)
    harness.feed("A", row: 3)
    harness.tracker.reset()
    #expect(harness.tracker.blocks.isEmpty)
    #expect(!harness.tracker.isAtPrompt)
    #expect(harness.tracker.promptGeneration == 2)
    #expect(harness.tracker.cwd == URL(filePath: "/tmp", directoryHint: .isDirectory))
    harness.feed("C", ProtocolFixture.base64("ls"), row: 4)
    #expect(harness.tracker.blocks.isEmpty)
  }

  @Test func resetWithARunningCommandStillSendsItToHistory() throws {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("C", ProtocolFixture.base64("tail -f app.log"), row: 1)
    harness.tracker.reset()
    harness.feed("D", "130", row: 2)
    #expect(harness.tracker.blocks.isEmpty)
    let recorded = try #require(harness.finished.first)
    #expect(harness.finished.count == 1)
    #expect(recorded.command == "tail -f app.log")
    #expect(recorded.exitCode == nil)
  }

  @Test func beginSessionStartsFromScratchExceptTheGeneration() {
    let harness = TrackerHarness()
    harness.feed("cwd", ProtocolFixture.base64("/tmp"), row: 0)
    harness.runCommand("ls", row: 0)
    harness.tracker.beginSession(SessionID())
    #expect(harness.tracker.blocks.isEmpty)
    #expect(harness.tracker.cwd == nil)
    #expect(!harness.tracker.isAtPrompt)
    #expect(harness.tracker.promptGeneration == 1)
  }

  @Test func desynchronizeClosesOpenBlocksAndIgnoresMarksUntilTheNextPrompt() throws {
    let harness = TrackerHarness()
    harness.runCommand("ok", row: 0)
    harness.feed("A", row: 3)
    harness.feed("C", ProtocolFixture.base64("yes"), row: 4)
    harness.tracker.desynchronize()

    let closed = try #require(harness.tracker.blocks.last)
    #expect(closed.state == .finished)
    #expect(closed.exitCode == nil)
    #expect(harness.tracker.blocks.first?.exitCode == 0)
    #expect(!harness.tracker.isAtPrompt)
    #expect(harness.tracker.insertionToken() == nil)

    harness.feed("C", ProtocolFixture.base64("ignored"), row: 5)
    harness.feed("D", "0", row: 6)
    harness.feed("cwd", ProtocolFixture.base64("/etc"), row: 6)
    #expect(harness.tracker.blocks.count == 2)
    #expect(harness.tracker.cwd == nil)

    harness.feed("A", row: 7)
    #expect(harness.tracker.blocks.count == 3)
    #expect(harness.tracker.blocks.last?.state == .editing)
    #expect(harness.tracker.insertionToken() != nil)
  }

  @Test func desynchronizeDiscardsAnEditingBlock() {
    let harness = TrackerHarness()
    harness.runCommand("ok", row: 0)
    harness.feed("A", row: 3)
    harness.tracker.desynchronize()
    #expect(harness.tracker.blocks.count == 1)
    #expect(harness.tracker.blocks.allSatisfy { $0.command == "ok" })
    #expect(harness.finished.map(\.command) == ["ok"])
  }

  // MARK: Accesibilidad

  @Test func accessibilityLabelsDescribeEachState() throws {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("C", ProtocolFixture.base64("swift test"), row: 1)
    harness.clocks.elapsed = .milliseconds(3_900)
    harness.feed("D", "1", row: 2)
    harness.feed("A", row: 3)
    harness.feed("C", ProtocolFixture.base64("ls"), row: 4)
    harness.clocks.elapsed = .milliseconds(4_300)
    harness.feed("D", "0", row: 5)
    harness.feed("A", row: 6)
    harness.feed("C", ProtocolFixture.base64("make"), row: 7)
    harness.feed("A", row: 8)
    harness.feed("C", ProtocolFixture.base64("a\nb"), row: 9)
    harness.feed("A", row: 10)

    let labels = harness.tracker.blocks.map { harness.tracker.accessibilityLabel(for: $0) }
    #expect(
      labels[0]
        == "swift test, failed with code 1 in 3\(Locale.current.decimalSeparator ?? ".")9 seconds")
    #expect(labels[1] == "ls, succeeded in 0\(Locale.current.decimalSeparator ?? ".")4 seconds")
    #expect(labels[2] == "make, finished without an exit code")
    #expect(labels[3] == "Command without text, finished without an exit code")
    #expect(labels[4] == "Prompt, waiting for a command")

    harness.feed("C", ProtocolFixture.base64("top"), row: 11)
    #expect(
      harness.tracker.accessibilityLabel(for: try #require(harness.tracker.blocks.last))
        == "top, running")
  }
}
