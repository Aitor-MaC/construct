import SwiftTerm
import Testing

/// 05-security I1 (CWE-787): con SwiftTerm 1.99.3, un DECSLRM inválido dejaba una región de una
/// columna en la última; un carácter ancho ahí dejaba la línea con una celda recortada de más, y
/// estrechar el panel (split, inspector, Quake) hacía que `reflowNarrower` copiara fuera del heap.
@MainActor @Suite struct ReflowBoundsTests {
  private static let hostileOutput = "\u{1b}[?69h\u{1b}[670s\u{1b}[F漢\n"

  @Test(arguments: [40, 79, 20, 10])
  func wideCharacterInAnInvalidMarginSurvivesANarrowerResize(cols: Int) {
    let terminal = Terminal(
      delegate: HeadlessHost(), options: TerminalOptions(cols: 80, rows: 24, scrollback: 100))
    terminal.feed(text: Self.hostileOutput)
    #expect(Self.linesExceedingTheirSize(in: terminal).isEmpty)

    terminal.resize(cols: cols, rows: 24)
    #expect(Self.linesExceedingTheirSize(in: terminal).isEmpty)
  }

  private static func linesExceedingTheirSize(in terminal: Terminal) -> [Int] {
    (0..<terminal.rows).filter { row in
      guard let line = terminal.getLine(row: row) else { return false }
      return line.getTrimmedLength() > line.count
    }
  }
}
