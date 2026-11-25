import MacterminalCore
import MacterminalTerminal
import SwiftUI

extension FirstCommandFlag {
  /// Dominio propio y vaciado en cada preview: nunca lee ni escribe las preferencias de la app.
  static func preview() -> FirstCommandFlag {
    let domain = "com.aitorgarcia.Macterminal.previews"
    // `suiteName:` solo devuelve nil con el dominio global o el de la propia app.
    let defaults = UserDefaults(suiteName: domain)!
    defaults.removePersistentDomain(forName: domain)
    return FirstCommandFlag(defaults: defaults)
  }
}

/// Datos de las previews: un `BlockTracker` alimentado con payloads 7777 reales (nonce + verbo,
/// como los entrega el handler de SwiftTerm) pasados por `OSCParser`, con un ancla por marca.
@MainActor private final class PreviewSession {
  let nonce = SessionNonce.random()
  let tracker = BlockTracker(wallClock: Date.init, monotonic: { ContinuousClock.now })
  let firstCommand: FirstCommandFlag
  private var rows: [RowAnchor: Int] = [:]
  private(set) var cursorRow = 0

  init() {
    let firstCommand = FirstCommandFlag.preview()
    self.firstCommand = firstCommand
    tracker.onCommandStarted = { firstCommand.markSet() }
    tracker.beginSession(SessionID())
    feed("cwd", Self.base64("/Users/neo/Projects/zion"), row: 0)
  }

  var resolve: (RowAnchor) -> Int? { { [rows] in rows[$0] } }

  func feed(_ fields: String..., row: Int) {
    let payload = ArraySlice(Array(([nonce.hex] + fields).joined(separator: ";").utf8))
    guard let event = OSCParser.parse(payload: payload, nonce: nonce) else { return }
    let anchor = RowAnchor(id: UInt64(rows.count))
    rows[anchor] = row
    tracker.handle(event, anchor: anchor)
    cursorRow = row
  }

  /// Prompt de dos líneas, comando y `output` filas de salida.
  func run(_ command: String, exit: String, output: Int) {
    let row = cursorRow
    feed("A", row: row)
    feed("B", row: row + 1)
    feed("C", Self.base64(command), row: row + 2)
    feed("D", exit, row: row + 2 + output)
  }

  func prompt() { feed("A", row: cursorRow) }

  func start(_ command: String) {
    let row = cursorRow
    feed("A", row: row)
    feed("B", row: row + 1)
    feed("C", Self.base64(command), row: row + 2)
    cursorRow = row + 6
  }

  func viewport(rows visible: Int = 24) -> ViewportSnapshot {
    ViewportSnapshot(
      topRow: max(0, cursorRow + 2 - visible), rows: visible, columns: 100,
      cellSize: CGSize(width: 7.8, height: 18.2), occupiedRows: IndexSet(),
      cursor: GridPosition(col: 2, row: cursorRow + 1))
  }

  private static func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }
}

private struct BlocksPreview: View {
  let session: PreviewSession
  var integrationAvailable = true
  var selectFirst = false
  @State private var state = BlockOverlayState()

  var body: some View {
    let viewport = session.viewport()
    ZStack {
      BlocksBackdropView(
        tracker: session.tracker, state: state, viewport: viewport, resolve: session.resolve)
      BlocksOverlayView(
        tracker: session.tracker, state: state, viewport: viewport, resolve: session.resolve,
        textProvider: { _ in "" }, insertIntoPrompt: { _, _ in .inserted },
        integrationAvailable: integrationAvailable, openPalette: {},
        firstCommand: session.firstCommand)
    }
    .frame(width: 780, height: 24 * 18.2)
    .background(BlockTokens.background)
    .onAppear {
      if selectFirst, let first = session.tracker.blocks.first { state.select(first.id) }
    }
  }
}

#Preview("Successful block") {
  let session = PreviewSession()
  session.run("swift build", exit: "0", output: 4)
  session.prompt()
  return BlocksPreview(session: session)
}

#Preview("Failed block, selected") {
  let session = PreviewSession()
  session.run("swift test", exit: "1", output: 6)
  session.prompt()
  return BlocksPreview(session: session, selectFirst: true)
}

#Preview("Running") {
  let session = PreviewSession()
  session.run("git status", exit: "0", output: 3)
  session.start("swift build -c release")
  return BlocksPreview(session: session)
}

#Preview("Empty state") {
  let session = PreviewSession()
  session.prompt()
  return BlocksPreview(session: session)
}

#Preview("No integration") {
  BlocksPreview(session: PreviewSession(), integrationAvailable: false)
}

#Preview("5000 blocks") {
  let session = PreviewSession()
  for index in 0..<BlockTracker.maxBlocks {
    session.run("echo \(index)", exit: index % 7 == 0 ? "1" : "0", output: 1)
  }
  session.prompt()
  return BlocksPreview(session: session)
}
