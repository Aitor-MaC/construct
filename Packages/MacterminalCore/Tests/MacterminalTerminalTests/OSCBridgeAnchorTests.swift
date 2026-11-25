import Foundation
import MacterminalCore
import Testing

@testable import MacterminalTerminal

/// Criterio 2 y A1: un ancla resuelve a su línea real o a `nil`, nunca a otra línea.
@MainActor @Suite struct OSCBridgeAnchorTests {
  /// Cada bloque que sobrevive tiene su prompt donde está el prompt y su salida exacta.
  private func expectAnchorsPointToTheirLines(
    _ harness: BridgeHarness, outputs: [String: String], sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for block in harness.blocks.blocks {
      if let prompt = harness.text(of: block.promptAnchor) {
        #expect(prompt.hasPrefix(" ~ "), sourceLocation: sourceLocation)
      }
      guard block.state == .finished, let command = block.command,
        let output = harness.output(of: block)
      else { continue }
      #expect(output == outputs[command], "\(command)", sourceLocation: sourceLocation)
    }
  }

  @Test func viewportUsesTheSameRowsAsTheAnchors() throws {
    let harness = try BridgeHarness(rows: 24, scrollback: 30)
    let fixture = harness.fixture
    harness.feedAndSettle(fixture.preamble + fixture.echoHola(printing: (1...100).map { "l\($0)" }))
    harness.feedAndSettle(fixture.finalPrompt)
    let viewport = harness.bridge.viewportSnapshot(cellSize: CGSize(width: 8, height: 17))
    let prompt = try #require(harness.blocks.blocks.last.flatMap { harness.bridge.resolve($0.promptAnchor) })
    #expect(viewport.topRow > 0)
    #expect(viewport.rows == 24 && viewport.columns == 120)
    #expect(viewport.occupiedRows.contains(prompt))
    #expect(viewport.cursor?.row == prompt + 1)
    #expect(harness.bridge.scrollIndex(forRow: viewport.topRow) == harness.terminal.buffer.yDisp)
  }

  @Test(arguments: [40, 500])
  func threeThousandLinesWithSaturatedScrollback(scrollback: Int) throws {
    let harness = try BridgeHarness(rows: 24, scrollback: scrollback)
    let fixture = harness.fixture
    let lines = (1...3000).map { "linea \($0)" }
    harness.feedAndSettle(
      fixture.preamble + fixture.echoHola + fixture.echoHola(printing: lines) + fixture.exitThree
        + fixture.finalPrompt)
    let blocks = harness.blocks.blocks
    // Los dos primeros prompts salieron del scrollback: sus bloques se podan.
    #expect(blocks.map(\.command) == ["(exit 3)", nil])
    #expect(harness.output(of: blocks[0]) == "")
    expectAnchorsPointToTheirLines(harness, outputs: ["(exit 3)": ""])
  }

  @Test func recycledLinesNeverResolve() throws {
    let harness = try BridgeHarness(rows: 24, scrollback: 30)
    let fixture = harness.fixture
    var stream = fixture.preamble
    for index in 1...40 {
      stream += fixture.echoHola(printing: ["salida \(index)", "fin \(index)"])
    }
    harness.feedAndSettle(stream, chunk: 512)
    #expect(!harness.blocks.blocks.isEmpty)
    #expect(harness.blocks.blocks.count < 40)
    for block in harness.blocks.blocks {
      #expect(harness.text(of: block.promptAnchor)?.hasPrefix(" ~ ") == true)
      if let output = harness.output(of: block) {
        #expect(output.hasPrefix("salida ") && output.contains("\nfin "))
      }
    }
  }

  @Test(arguments: [(60, 20), (200, 40), (121, 30)])
  func resizeKeepsOrDropsAnchorsButNeverMovesThem(cols: Int, rows: Int) throws {
    let harness = try BridgeHarness()
    let fixture = harness.fixture
    harness.feedAndSettle(fixture.bytes)
    harness.resize(cols: cols, rows: rows)
    expectAnchorsPointToTheirLines(
      harness, outputs: ["echo hola": "hola", "(exit 3)": "", " echo oculto": "oculto", "print -r -- 'ñ 日本 %'": "ñ 日本 %"])
    // Y el siguiente comando se ancla bien. Los bytes se grabaron a 120 columnas: más estrecho,
    // el relleno `%` de PROMPT_SP de zsh ocuparía dos filas.
    guard cols >= 120 else { return }
    harness.feedAndSettle(fixture.echoHola)
    let last = try #require(harness.blocks.blocks.last)
    #expect(last.command == "echo hola")
    #expect(harness.output(of: last) == "hola")
  }

  @Test func resizeWhileInAlternateScreenIsAppliedOnReturn() throws {
    let harness = try BridgeHarness()
    let fixture = harness.fixture
    harness.feedAndSettle(fixture.preamble + fixture.echoHola)
    harness.feedAndSettle(try Terminfo.capability("smcup"))
    harness.resize(cols: 150, rows: 20)
    harness.feedAndSettle(try Terminfo.capability("rmcup") + fixture.exitThree + fixture.finalPrompt)
    #expect(harness.blocks.blocks.map(\.command) == ["echo hola", "(exit 3)", nil])
    expectAnchorsPointToTheirLines(harness, outputs: ["echo hola": "hola", "(exit 3)": ""])
  }

  @Test func clearDropsOldBlocksAndAnchorsTheNewPrompt() throws {
    let harness = try BridgeHarness(rows: 24, scrollback: 500)
    let fixture = harness.fixture
    let clear = try Terminfo.capability("clear")
    #expect(clear.contains(0x4A))  // ED: `CSI 2 J` y `CSI 3 J`
    harness.feedAndSettle(fixture.preamble + fixture.echoHola + fixture.exitThree)
    let clearCycle = fixture.echoHola.replacing(Array("hola\r\n".utf8), with: clear)
    harness.feedAndSettle(clearCycle + fixture.echoHola + fixture.finalPrompt)
    let blocks = harness.blocks.blocks
    #expect(blocks.last?.state == .editing)
    #expect(blocks.contains { $0.command == "echo hola" && harness.output(of: $0) == "hola" })
    expectAnchorsPointToTheirLines(harness, outputs: ["echo hola": "hola", "(exit 3)": ""])
  }

  /// ⌘K en el prompt: reset, borrado propio y Ctrl-L; el widget `clear-screen` de la integración
  /// vuelve el cursor al origen y anuncia el prompt redibujado, que vuelve a admitir inserciones.
  @Test func commandKAtThePromptRearmsTheRedrawnPrompt() throws {
    let harness = try BridgeHarness(rows: 24, scrollback: 500)
    let fixture = harness.fixture
    harness.feedAndSettle(fixture.preamble + fixture.echoHola + fixture.finalPrompt)
    harness.bridge.reset()
    #expect(harness.blocks.insertionToken() == nil)
    let clearScreenWidget = Array("\u{1b}[H".utf8) + fixture.finalPrompt
    harness.feedAndSettle(Array("\u{1b}[H\u{1b}[2J\u{1b}[3J".utf8) + clearScreenWidget)
    let blocks = harness.blocks.blocks
    #expect(blocks.count == 1)
    #expect(blocks.first?.state == .editing)
    #expect(harness.blocks.isAtPrompt)
    #expect(harness.blocks.insertionToken() != nil)
    let prompt = try #require(blocks.first?.promptAnchor)
    #expect(harness.text(of: prompt)?.hasPrefix(" ~ ") == true)
  }
}
