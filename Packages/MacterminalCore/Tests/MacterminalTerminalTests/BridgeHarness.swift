import Foundation
import MacterminalCore
import SwiftTerm

@testable import MacterminalTerminal

/// Bytes reales grabados por el script de T3 (`ZshSessionTests.referenceSessionCoversEveryVerb`).
/// Solo se cambia el nonce grabado por el de la sesión del test, que `SessionNonce` no permite
/// fijar desde fuera.
struct ShellFixture {
  static let directory = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "../Fixtures/ShellIntegration").standardized
  static let promptMarker = Array("\u{1b}]133;A\u{07}".utf8)

  let recordedNonce: [UInt8]
  let bytes: [UInt8]

  init(nonce: SessionNonce) throws {
    recordedNonce = Array(try Data(contentsOf: Self.directory.appending(path: "zsh-session.nonce")))
    let recorded = Array(try Data(contentsOf: Self.directory.appending(path: "zsh-session.bin")))
    bytes = recorded.replacing(recordedNonce, with: Array(nonce.hex.utf8))
  }

  /// Lo grabado tal cual: lo que vería un programa que reprodujera las marcas sin el nonce real.
  var withRecordedNonce: [UInt8] {
    get throws { Array(try Data(contentsOf: Self.directory.appending(path: "zsh-session.bin"))) }
  }

  /// Trozos que empiezan en cada prompt: `[0]` es el arranque (cwd inicial), `[1...4]` los
  /// cuatro comandos (`echo hola`, `(exit 3)`, ` echo oculto`, `print … 'ñ 日本 %'`) y `[5]` el
  /// último prompt con la petición `# explica esto`.
  var parts: [[UInt8]] {
    let starts = [0] + bytes.ranges(of: Self.promptMarker).map(\.lowerBound) + [bytes.count]
    return zip(starts, starts.dropFirst()).map { Array(bytes[$0..<$1]) }
  }

  var preamble: [UInt8] { parts[0] }
  var echoHola: [UInt8] { parts[1] }
  var exitThree: [UInt8] { parts[2] }
  var finalPrompt: [UInt8] { parts[5] }

  /// `echo hola` con otra salida: las marcas siguen siendo las grabadas.
  func echoHola(printing lines: [String]) -> [UInt8] {
    let output = lines.map { $0 + "\r\n" }.joined()
    return echoHola.replacing(Array("hola\r\n".utf8), with: Array(output.utf8))
  }
}

/// Secuencias de terminfo generadas por `tput`, el mismo productor que usan `clear`, `vim` o `less`.
enum Terminfo {
  static func capability(_ name: String) throws -> [UInt8] {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/tput")
    process.arguments = [name]
    process.environment = ["TERM": "xterm-256color"]
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Array(data)
  }
}

final class HeadlessHost: TerminalDelegate {
  var sent: [UInt8] = []
  weak var bridge: OSCBridge?

  func send(source: Terminal, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }

  func bufferActivated(source: Terminal) {
    let bridge = bridge
    MainActor.assumeIsolated { bridge?.bufferActivated() }
  }
}

/// Turnos de MainActor bajo control del test: cada `run()` es un turno.
@MainActor final class ManualTurns {
  private var queued: [@MainActor () -> Void] = []
  var isEmpty: Bool { queued.isEmpty }

  func schedule(_ work: @escaping @MainActor () -> Void) { queued.append(work) }

  func runNext() {
    guard !queued.isEmpty else { return }
    queued.removeFirst()()
  }

  func runAll() {
    while !queued.isEmpty { runNext() }
  }
}

@MainActor final class BridgeHarness {
  let host = HeadlessHost()
  let terminal: Terminal
  let blocks: BlockTracker
  let bridge: OSCBridge
  let turns = ManualTurns()
  let nonce = SessionNonce.random()
  let session = SessionID()
  let fixture: ShellFixture
  var aiRequests: [(String, InsertionToken)] = []
  var titles: [String] = []

  init(cols: Int = 120, rows: Int = 30, scrollback: Int = 1000, integration: Bool = true) throws {
    let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
    let fixedInstant = ContinuousClock.Instant.now
    terminal = Terminal(
      delegate: host, options: TerminalOptions(cols: cols, rows: rows, scrollback: scrollback))
    blocks = BlockTracker(wallClock: { fixedDate }, monotonic: { fixedInstant })
    let turns = turns
    bridge = OSCBridge(terminal: terminal, blocks: blocks) { turns.schedule($0) }
    fixture = try ShellFixture(nonce: nonce)
    host.bridge = bridge
    bridge.begin(session: session, nonce: integration ? nonce : nil)
    bridge.onAIRequest = { [unowned self] in aiRequests.append(($0, $1)) }
    bridge.onTitleChange = { [unowned self] in titles.append($0) }
  }

  func feed(_ bytes: [UInt8], chunk: Int? = nil) {
    let size = max(1, chunk ?? bytes.count)
    var start = 0
    while start < bytes.count {
      let end = min(bytes.count, start + size)
      bridge.feed { terminal.feed(byteArray: Array(bytes[start..<end])) }
      start = end
    }
  }

  func feedAndSettle(_ bytes: [UInt8], chunk: Int? = nil) {
    feed(bytes, chunk: chunk)
    turns.runAll()
  }

  func resize(cols: Int, rows: Int) {
    terminal.resize(cols: cols, rows: rows)
    bridge.terminalDidResize()
  }

  func text(of anchor: RowAnchor?) -> String? {
    guard let row = anchor.flatMap(bridge.resolve) else { return nil }
    return bridge.text(rows: row..<(row + 1))
  }

  func output(of block: CommandBlock) -> String? {
    blocks.outputRows(of: block, resolve: bridge.resolve).map(bridge.text(rows:))
  }

  func insert(_ text: String, token: InsertionToken) -> (InsertResult, [UInt8]) {
    var written: [UInt8] = []
    let result = bridge.insertIntoPrompt(text, token: token) { written.append(contentsOf: $0) }
    return (result, written)
  }
}

extension Array where Element == UInt8 {
  func repeated(_ count: Int) -> [UInt8] { Array(repeatElement(self, count: count).joined()) }
}
