import Foundation

@testable import MacterminalCore

/// Relojes fijos: la fecha y el instante solo avanzan cuando el test lo pide.
final class FixedClocks {
  var wall = Date(timeIntervalSince1970: 1_800_000_000)
  let origin = ContinuousClock.now
  var elapsed: Duration = .zero
  var instant: ContinuousClock.Instant { origin.advanced(by: elapsed) }
}

/// Alimenta un `BlockTracker` como lo hará T7: bytes 7777 → `OSCParser` → `handle`, con un ancla
/// nueva por marca que el test puede resolver, mover o borrar.
@MainActor final class TrackerHarness {
  let nonce = SessionNonce.random()
  let clocks = FixedClocks()
  let tracker: BlockTracker
  let session = SessionID()
  private(set) var finished: [CommandBlock] = []
  private(set) var commandsStarted = 0
  private(set) var anchors: [RowAnchor] = []
  var rows: [RowAnchor: Int] = [:]

  init(beginSession: Bool = true) {
    let clocks = clocks
    tracker = BlockTracker(wallClock: { clocks.wall }, monotonic: { clocks.instant })
    tracker.onBlockFinished = { [unowned self] block in finished.append(block) }
    tracker.onCommandStarted = { [unowned self] in commandsStarted += 1 }
    if beginSession { tracker.beginSession(session) }
  }

  var resolve: (RowAnchor) -> Int? { { [rows] anchor in rows[anchor] } }

  /// Devuelve el evento si el parser lo aceptó.
  @discardableResult
  func feed(_ fields: String..., row: Int) -> ShellEvent? {
    feed(payload: ArraySlice(Array(([nonce.hex] + fields).joined(separator: ";").utf8)), row: row)
  }

  @discardableResult
  func feed(payload: ArraySlice<UInt8>, row: Int) -> ShellEvent? {
    guard let event = OSCParser.parse(payload: payload, nonce: nonce) else { return nil }
    let anchor = RowAnchor(id: UInt64(anchors.count))
    anchors.append(anchor)
    rows[anchor] = row
    tracker.handle(event, anchor: anchor)
    return event
  }

  /// Ciclo completo de un comando: prompt en `row`, salida desde `row + 1` hasta `row + outputLines`.
  func runCommand(_ command: String, exit: String = "0", row: Int, outputLines: Int = 1) {
    feed("A", row: row)
    feed("B", row: row)
    feed("C", ProtocolFixture.base64(command), row: row + 1)
    feed("D", exit, row: row + 1 + outputLines)
  }
}
