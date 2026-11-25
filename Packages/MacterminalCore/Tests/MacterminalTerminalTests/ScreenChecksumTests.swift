import SwiftTerm
import Testing

/// Contrato con SwiftTerm del que depende `MatrixTerminalView` (CWE-200): con
/// `enableRectangularAreaChecksum = false`, DECRQCRA responde `0000` en vez de la suma real de la
/// pantalla, que pidiendo rectángulos de 1×1 dejaría leerla carácter a carácter. Se fija a mano
/// porque el valor por defecto de SwiftTerm es `true` en compilaciones Debug.
@MainActor @Suite struct ScreenChecksumTests {
  @Test(arguments: ["\u{1b}[7;1;1;1;1;1*y", "\u{1b}[7;1;1;1;4;20*y"])
  func checksumRequestsAreAnsweredWithZeros(request: String) {
    let host = HeadlessHost()
    let terminal = Terminal(
      delegate: host, options: TerminalOptions(cols: 20, rows: 4, scrollback: 10))
    terminal.enableRectangularAreaChecksum = false
    terminal.feed(text: "secreto " + String(repeating: "日本語", count: 4))
    host.sent = []

    terminal.feed(text: request)

    #expect(host.sent == Array("\u{1b}P7!~0000\u{1b}\\".utf8))
  }
}
