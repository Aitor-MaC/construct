import Foundation
import Testing

@testable import MacterminalCore

@Suite(.language("en")) struct ContractsTests {
  @Test func opacityRejectsNonFiniteAndClampsRange() {
    var config = TerminalConfig(shell: "/bin/zsh")
    config.backgroundOpacity = 0.1
    #expect(config.backgroundOpacity == 0.5)
    config.backgroundOpacity = 2
    #expect(config.backgroundOpacity == 1)
    config.backgroundOpacity = .nan
    #expect(config.backgroundOpacity == 1)
    config.backgroundOpacity = 0.75
    #expect(config.backgroundOpacity == 0.75)
  }
  @Test func colorValidationAndContrast() throws {
    #expect(RGB(hex: "broken") == nil)
    #expect(RGB(hex: "#FFFFFG") == nil)
    let white = try #require(RGB(hex: "FFFFFF"))
    let black = try #require(RGB(hex: "000000"))
    #expect(white.contrastRatio(with: black) == 21)
    #expect(abs(MatrixPalette.fg.contrastRatio(with: MatrixPalette.bg) - 15.7) < 0.1)
    #expect(MatrixPalette.ansi.count == 16)
    for color in MatrixPalette.ansi.dropFirst() {
      #expect(color.contrastRatio(with: MatrixPalette.bg) >= 4.5)
    }
  }
  @Test func viewportClipsAbsoluteCoordinates() {
    let snapshot = ViewportSnapshot(
      topRow: 2000, rows: 40, columns: 80, cellSize: CGSize(width: 8, height: 16),
      occupiedRows: IndexSet([2000, 2005, 2100]), cursor: GridPosition(col: 2, row: 2100))
    #expect(snapshot.viewportOccupiedRows() == IndexSet([0, 5]))
    #expect(snapshot.viewportCursor() == nil)
    let visible = ViewportSnapshot(
      topRow: 2000, rows: 40, columns: 80, cellSize: CGSize(width: 0, height: 0), occupiedRows: [],
      cursor: GridPosition(col: 3, row: 2005))
    #expect(visible.viewportCursor() == GridPosition(col: 3, row: 5))
  }
  @Test func shortcutsRejectMalformedAndNormalize() {
    #expect(KeyShortcut(configString: "ctrl+grave")?.key == "grave")
    #expect(KeyShortcut(configString: "shift+cmd+p") == KeyShortcut(configString: "cmd+shift+p"))
    #expect(KeyShortcut(configString: "ctrl+ctrl+a") == nil)
    #expect(KeyShortcut(configString: "bogus+a") == nil)
    #expect(KeyShortcut(configString: "cmd+") == nil)
    let shortcuts = TerminalAction.catalog.compactMap(\.shortcut)
    #expect(Set(shortcuts).count == shortcuts.count)
  }
  /// Copiar y Copiar salida del bloque seleccionado con ⌘↑/⌘↓ tienen camino de teclado.
  @Test func selectedBlockCanBeCopiedFromTheKeyboard() {
    #expect(TerminalAction.catalog.contains(.copyBlockCommand))
    #expect(TerminalAction.catalog.contains(.copyBlockOutput))
    #expect(TerminalAction.copyBlockCommand.shortcut == KeyShortcut(configString: "cmd+shift+c"))
    #expect(TerminalAction.copyBlockOutput.shortcut == KeyShortcut(configString: "cmd+alt+shift+c"))
    #expect(TerminalAction.copyBlockCommand.title == "Copy Block Command")
    #expect(TerminalAction.copyBlockOutput.title == "Copy Block Output")
  }
  @Test func intensityAndUnfinishedDuration() {
    #expect(Intensity.sutil.profile.speed == 8...14)
    #expect(Intensity.equilibrado.profile.trailLength == 10...20)
    #expect(Intensity.inmersivo.profile.headAlpha == 0.45)
    for intensity in Intensity.allCases { #expect(intensity.profile.textRowAlphaCap == 0.10) }
    #expect(CommandBlock(promptAnchor: RowAnchor(id: 1)).duration == nil)
    #expect(SessionID() != SessionID())
  }
}
