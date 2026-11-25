import Foundation
import MacterminalCore
import Testing

@testable import MacterminalTerminal

private struct BlockSummary: Equatable {
  let command: String?
  let exitCode: Int32?
  let state: CommandBlock.State
  let promptRow: Int?
  let output: String?
}

@MainActor private func summaries(_ harness: BridgeHarness) -> [BlockSummary] {
  harness.blocks.blocks.map { block in
    BlockSummary(
      command: block.command, exitCode: block.exitCode, state: block.state,
      promptRow: harness.bridge.resolve(block.promptAnchor), output: harness.output(of: block))
  }
}

@MainActor @Suite struct OSCBridgeTests {
  // MARK: Puerta de fixtures (criterio 3)

  @Test func recordedSessionProducesTheExpectedBlocks() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes)
    let blocks = harness.blocks.blocks
    #expect(blocks.map(\.command) == ["echo hola", "(exit 3)", " echo oculto", "print -r -- 'ñ 日本 %'", nil])
    #expect(blocks.map(\.exitCode) == [0, 3, 0, 0, nil])
    #expect(blocks.map(\.recordInHistory) == [true, true, false, true, true])
    #expect(blocks.last?.state == .editing)
    #expect(harness.output(of: blocks[0]) == "hola")
    #expect(harness.output(of: blocks[1]) == "")
    #expect(harness.output(of: blocks[3]) == "ñ 日本 %")
    #expect(blocks.allSatisfy { harness.text(of: $0.promptAnchor)?.hasPrefix(" ~ ") == true })
    #expect(harness.blocks.cwd?.path().hasSuffix("/home/") == true)
    #expect(harness.aiRequests.map(\.0) == ["explica esto"])
    #expect(harness.aiRequests.first?.1 == harness.blocks.insertionToken())
    #expect(!harness.bridge.hasPendingWork)
  }

  // MARK: Orden del lote (criterio 10)

  @Test func chunkingDoesNotChangeTheBlocks() throws {
    var results: [[BlockSummary]] = []
    for chunk in [1, 4096, nil] {
      let harness = try BridgeHarness()
      let fixture = harness.fixture
      let stream = fixture.bytes + fixture.parts[1...4].joined() + fixture.finalPrompt
      harness.feedAndSettle(stream, chunk: chunk)
      results.append(summaries(harness))
    }
    // 4 comandos grabados + 4 repetidos + el prompt final; el prompt `editing` abandonado de la
    // grabación se descarta al llegar el siguiente A.
    #expect(results[0].count == 9)
    #expect(results[0] == results[1])
    #expect(results[1] == results[2])
  }

  @Test func moreThanOneBatchInASingleFeedLosesNothing() throws {
    let harness = try BridgeHarness(scrollback: 2000)
    let fixture = harness.fixture
    harness.feed(fixture.preamble + fixture.echoHola.repeated(100))
    #expect(harness.bridge.hasPendingWork)
    #expect(!harness.turns.isEmpty)
    harness.turns.runAll()
    #expect(harness.blocks.blocks.count == 100)
    #expect(harness.blocks.blocks.allSatisfy { $0.command == "echo hola" && $0.exitCode == 0 })
    #expect(!harness.bridge.hasPendingWork)
  }

  /// Arranque = 1 elemento (cwd) y cada `echo hola` = A, B, C, D, cwd: con 3 arranques el `C`
  /// del bloque 50 es el elemento 256, el último del primer tramo.
  @Test func commandStartedAtPosition256IsAppliedInTheFirstBatch() throws {
    let harness = try BridgeHarness(scrollback: 2000)
    let fixture = harness.fixture
    harness.feed(fixture.preamble.repeated(3) + fixture.echoHola.repeated(60))
    let blocks = harness.blocks.blocks
    #expect(blocks.count == 51)
    #expect(blocks.last?.state == .running)
    #expect(blocks.last?.command == "echo hola")
    harness.turns.runAll()
    #expect(harness.blocks.blocks.count == 60)
  }

  @Test func alternateScreenInsideOneFeedCreatesNoBlocks() throws {
    let harness = try BridgeHarness()
    let fixture = harness.fixture
    let enter = try Terminfo.capability("smcup")
    let leave = try Terminfo.capability("rmcup")
    #expect(!enter.isEmpty && !leave.isEmpty)
    harness.feedAndSettle(
      fixture.preamble + fixture.echoHola + enter + fixture.exitThree + fixture.echoHola + leave
        + fixture.echoHola)
    #expect(harness.blocks.blocks.map(\.command) == ["echo hola", "echo hola"])
    #expect(harness.blocks.blocks.allSatisfy { $0.exitCode == 0 })
  }

  /// 1 + 5·k: el elemento 4097 es el `A` del bloque 819, que rearma el tracker.
  @Test func overflowDesynchronizesAndTheNextPromptRearms() throws {
    let harness = try BridgeHarness(scrollback: 10_000)
    let fixture = harness.fixture
    harness.feedAndSettle(fixture.preamble + fixture.echoHola.repeated(900))
    let blocks = harness.blocks.blocks
    #expect(blocks.count == 81)
    #expect(blocks.allSatisfy { $0.command == "echo hola" && $0.exitCode == 0 })
    #expect(blocks.allSatisfy { harness.output(of: $0) == "hola" })
  }

  @Test func pendingEventsOfAnEndedSessionAreDiscarded() throws {
    let harness = try BridgeHarness(scrollback: 2000)
    let fixture = harness.fixture
    harness.feed(fixture.preamble + fixture.echoHola.repeated(100))
    let appliedBeforeEnd = harness.blocks.blocks.count
    harness.bridge.end()
    harness.turns.runAll()
    #expect(harness.blocks.blocks.count == appliedBeforeEnd)
    #expect(!harness.bridge.hasPendingWork)
  }

  // MARK: Marcas sin el nonce de la sesión (criterio 4, S7)

  @Test func marksWithAnotherNonceAreIgnored() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(try harness.fixture.withRecordedNonce)
    #expect(harness.blocks.blocks.isEmpty)
    #expect(harness.blocks.cwd == nil)
    #expect(harness.aiRequests.isEmpty)
    #expect(!harness.bridge.sawAuthenticatedPrompt)
  }

  @Test func marksWithoutNonceAreIgnored() throws {
    let harness = try BridgeHarness()
    let fixture = harness.fixture
    let stripped = try fixture.withRecordedNonce.replacing(fixture.recordedNonce + [0x3B], with: [])
    harness.feedAndSettle(stripped)
    #expect(harness.blocks.blocks.isEmpty)
    #expect(harness.blocks.cwd == nil)
    #expect(harness.aiRequests.isEmpty)
  }

  @Test func withoutIntegrationEvenValidMarksAreIgnored() throws {
    let harness = try BridgeHarness(integration: false)
    harness.feedAndSettle(harness.fixture.bytes)
    #expect(harness.blocks.blocks.isEmpty)
    #expect(harness.aiRequests.isEmpty)
    #expect(!harness.bridge.sawAuthenticatedPrompt)
  }

  @Test func firstAuthenticatedPromptIsRecorded() throws {
    let harness = try BridgeHarness()
    harness.feed(harness.fixture.preamble)
    #expect(!harness.bridge.sawAuthenticatedPrompt)
    harness.feed(harness.fixture.echoHola)
    #expect(harness.bridge.sawAuthenticatedPrompt)
  }

  // MARK: Títulos (criterio 6, I2)

  @Test func titleIsSanitizedAndNeverReportedBack() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(Array("\u{1b}]2;;touch pwned\n\u{07}\u{1b}[21t\u{1b}]0;vim\u{1b}\\".utf8))
    #expect(harness.titles == [";touch pwned", "vim"])
    #expect(!harness.host.sent.contains(0x0A))
    #expect(!String(decoding: harness.host.sent, as: UTF8.self).contains("touch"))
  }
}
