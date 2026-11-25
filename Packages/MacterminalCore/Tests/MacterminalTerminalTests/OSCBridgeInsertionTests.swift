import Foundation
import MacterminalCore
import Testing

@testable import MacterminalTerminal

/// Criterio 7 (A8, I3, A11): la inserción solo escribe en el prompt para el que se pidió, con
/// todo lo recibido ya aplicado.
@MainActor @Suite struct OSCBridgeInsertionTests {
  @Test func currentTokenInsertsTheTextBracketedWithoutReturn() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes)
    #expect(harness.terminal.bracketedPasteMode)
    let token = try #require(harness.blocks.insertionToken())
    let (result, written) = harness.insert("ls -la ñ", token: token)
    #expect(result == .inserted)
    #expect(written == Array("\u{1b}[200~ls -la ñ\u{1b}[201~".utf8))
  }

  @Test func withoutBracketedPasteTheTextGoesAlone() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes + Array("\u{1b}[?2004l".utf8))
    let token = try #require(harness.blocks.insertionToken())
    let (result, written) = harness.insert("git status", token: token)
    #expect(result == .inserted)
    #expect(written == Array("git status".utf8))
  }

  @Test func staleAndForeignTokensWriteNothing() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes)
    let current = try #require(harness.blocks.insertionToken())
    let previous = InsertionToken(session: current.session, promptGeneration: current.promptGeneration - 1)
    let foreign = InsertionToken(session: SessionID(), promptGeneration: current.promptGeneration)
    for token in [previous, foreign] {
      let (result, written) = harness.insert("ls", token: token)
      #expect(result == .stale)
      #expect(written.isEmpty)
    }
  }

  @Test(arguments: [
    ("ls\n", InsertionRejection.controlCharacter),
    ("ls\r", .controlCharacter),
    ("a\u{1b}[201~; rm -rf ~", .controlCharacter),
    ("echo \u{202e}txt", .bidiControl),
    (String(repeating: "a", count: PromptInsertion.maxUTF8Length + 1), .tooLong),
  ])
  func unsafeTextWritesNothing(text: String, rejection: InsertionRejection) throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes)
    let token = try #require(harness.blocks.insertionToken())
    let (result, written) = harness.insert(text, token: token)
    #expect(result == .unsafe(rejection))
    #expect(written.isEmpty)
  }

  @Test func runningCommandIsNotAPrompt() throws {
    let harness = try BridgeHarness()
    let fixture = harness.fixture
    let start = try #require(fixture.echoHola.ranges(of: Array("\u{1b}]133;C".utf8)).first)
    let finish = try #require(fixture.echoHola.ranges(of: Array("\u{1b}]133;D".utf8)).first)
    harness.feedAndSettle(fixture.preamble + Array(fixture.echoHola[..<start.lowerBound]))
    let token = try #require(harness.blocks.insertionToken())
    harness.feedAndSettle(Array(fixture.echoHola[start.lowerBound..<finish.lowerBound]))
    #expect(harness.blocks.blocks.last?.state == .running)
    let (result, written) = harness.insert("ls", token: token)
    #expect(result == .notAtPrompt)
    #expect(written.isEmpty)
  }

  @Test func alternateScreenIsNotAPrompt() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes)
    let token = try #require(harness.blocks.insertionToken())
    harness.feedAndSettle(try Terminfo.capability("smcup"))
    let (result, written) = harness.insert("ls", token: token)
    #expect(result == .notAtPrompt)
    #expect(written.isEmpty)
  }

  /// Con 4 arranques, el `C` del bloque 50 es el elemento 257: el primer tramo deja ese bloque
  /// en `editing` y un token que parece vigente.
  @Test func insertionBetweenTwoDrainTurnsIsStale() throws {
    let harness = try BridgeHarness(scrollback: 2000)
    let fixture = harness.fixture
    harness.feed(fixture.preamble.repeated(4) + fixture.echoHola.repeated(60))
    #expect(harness.blocks.blocks.last?.state == .editing)
    let token = try #require(harness.blocks.insertionToken())
    let (result, written) = harness.insert("ls", token: token)
    #expect(result == .stale)
    #expect(written.isEmpty)
    harness.turns.runAll()
    #expect(harness.blocks.blocks.count == 60)
    #expect(harness.insert("ls", token: token).0 == .stale)
  }

  @Test func pendingResetMakesTheTokenStale() throws {
    let harness = try BridgeHarness(scrollback: 2000)
    let fixture = harness.fixture
    harness.feedAndSettle(fixture.bytes)
    let token = try #require(harness.blocks.insertionToken())
    harness.feed(fixture.echoHola.repeated(60) + fixture.finalPrompt)
    harness.bridge.reset()
    #expect(harness.insert("ls", token: token).0 == .stale)
    harness.turns.runAll()
    #expect(harness.blocks.blocks.isEmpty)
    #expect(harness.insert("ls", token: token).1.isEmpty)
  }

  @Test func resetWithNothingPendingAppliesAtOnce() throws {
    let harness = try BridgeHarness()
    harness.feedAndSettle(harness.fixture.bytes)
    let token = try #require(harness.blocks.insertionToken())
    harness.bridge.reset()
    #expect(harness.blocks.blocks.isEmpty)
    #expect(harness.insert("ls", token: token).0 == .notAtPrompt)
  }
}
