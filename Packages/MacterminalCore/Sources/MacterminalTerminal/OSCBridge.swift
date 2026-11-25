import Foundation
import MacterminalCore
import OSLog
import SwiftTerm

public enum InsertResult: Sendable, Equatable {
  case inserted, notAtPrompt, stale
  case unsafe(InsertionRejection)
}

/// Une el `Terminal` de SwiftTerm con el `BlockTracker` de un panel. Las marcas 7777 se leen
/// durante el `feed` (síncrono, en MainActor), se autentican con el nonce de la sesión y se
/// encolan con el ancla de la fila del cursor en ese instante; después de cada `feed` la cola se
/// aplica en orden, en tramos acotados por turno (A1, B1, A11).
///
/// Filas: número invariante de SwiftTerm (`totalLinesTrimmed` + índice en el buffer), el mismo
/// que `TerminalContentSnapshot.absoluteRow`. Un ancla guarda la línea por identidad y su fila;
/// solo resuelve si la línea sigue exactamente en esa fila, así que nunca apunta a otra línea.
@MainActor public final class OSCBridge {
  public static let shellIntegrationCode = 7777
  public static let batchSize = 256
  public static let maxPending = 4096

  private enum Item {
    case event(ShellEvent, RowAnchor)
    case screen(alternate: Bool)
    case reset
  }

  private struct AnchoredLine {
    weak var line: BufferLine?
    var row: Int
  }

  public var onAIRequest: ((String, InsertionToken) -> Void)?
  public var onTitleChange: ((String) -> Void)?
  /// `true` desde el primer `A` autenticado de la sesión: el arranque del shell terminó (I8).
  public private(set) var sawAuthenticatedPrompt = false

  private let terminal: Terminal
  private let blocks: BlockTracker
  private let scheduleNextTurn: (@escaping @MainActor () -> Void) -> Void
  private let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "osc")

  private var session: SessionID?
  private var nonce: SessionNonce?
  private var pending: [Item] = []
  private var nextPending = 0
  private var isFeeding = false
  private var drainScheduled = false
  private var rejectedInFeed = 0
  private var queuedAlternate = false
  private var appliedAlternate = false
  private var anchors: [UInt64: AnchoredLine] = [:]
  private var lastAnchorID: UInt64 = 0
  private var anchorsAddedSinceCompaction = false
  /// Se quitaron anclas fuera de un turno en que el tracker se pudiera podar (dentro del feed).
  private var needsPrune = false
  /// El buffer normal: mientras la pantalla alternativa está activa, `terminal.buffer` es otro.
  private var normalBuffer: Buffer
  private var observedTrimmed: Int
  private var anchoredGeometry: (cols: Int, rows: Int)

  /// `scheduleNextTurn` ejecuta el siguiente tramo en otro turno de MainActor; los tests lo
  /// sustituyen para decidir cuándo corre cada tramo.
  public init(
    terminal: Terminal, blocks: BlockTracker,
    scheduleNextTurn: @escaping (@escaping @MainActor () -> Void) -> Void
  ) {
    self.terminal = terminal
    self.blocks = blocks
    self.scheduleNextTurn = scheduleNextTurn
    normalBuffer = terminal.buffer
    observedTrimmed = terminal.buffer.totalLinesTrimmed
    anchoredGeometry = (terminal.cols, terminal.rows)
    // Los handlers corren dentro del `feed`, que este puente solo hace en el hilo principal.
    terminal.registerOscHandler(code: Self.shellIntegrationCode) { [weak self] payload in
      MainActor.assumeIsolated { self?.receive(payload) }
    }
    for code in [0, 1, 2] {
      terminal.registerOscHandler(code: code) { [weak self] payload in
        MainActor.assumeIsolated { self?.receiveTitle(code: code, payload: payload) }
      }
    }
  }

  // MARK: Sesión

  /// `nonce == nil`: shell sin integración, todas las marcas se descartan (S7).
  public func begin(session: SessionID, nonce: SessionNonce?) {
    discardPending()
    self.session = session
    self.nonce = nonce
    sawAuthenticatedPrompt = false
    blocks.beginSession(session)
  }

  /// Lo que quedara en la cola pertenece a un proceso que ya no existe.
  public func end() {
    discardPending()
    session = nil
    nonce = nil
    blocks.endSession()
  }

  // MARK: Entrada del emulador

  /// Envuelve cada `feed` del terminal: mientras dura, y hasta aplicar lo encolado, la inserción
  /// en el prompt se rechaza.
  public func feed(_ apply: () -> Void) {
    isFeeding = true
    apply()
    isFeeding = false
    enqueueScreenIfChanged()
    if rejectedInFeed > 0 {
      logger.debug("7777 rejected in batch: \(self.rejectedInFeed, privacy: .public)")
      rejectedInFeed = 0
    }
    noteTrimming()
    drainNow()
  }

  /// Desde `TerminalDelegate.bufferActivated`, que SwiftTerm llama dentro del `feed` al cambiar
  /// de pantalla. Al volver a la normal SwiftTerm aplica entonces un resize aplazado.
  public func bufferActivated() {
    if terminal.isCurrentBufferAlternate {
      noteTrimming()
    } else {
      normalBuffer = terminal.buffer
      if anchoredGeometry != (terminal.cols, terminal.rows) { rebaseline() }
    }
    enqueueScreenIfChanged()
  }

  /// Tras `Terminal.resize`: el reflow mueve las líneas de fila.
  public func terminalDidResize() {
    guard !terminal.isCurrentBufferAlternate else { return }
    rebaseline()
    pruneIfNeeded()
  }

  /// ⌘K: el reset va a la cola para aplicarse después de las marcas anteriores.
  public func reset() {
    enqueue(.reset)
    drainNow()
  }

  public var hasPendingWork: Bool { isFeeding || nextPending < pending.count }

  // MARK: Filas

  /// `nil` si la línea se recortó, se recicló o se movió, y mientras la pantalla alternativa
  /// oculta el buffer normal.
  public func resolve(_ anchor: RowAnchor) -> Int? {
    guard !terminal.isCurrentBufferAlternate, let entry = anchors[anchor.id],
      let line = entry.line, terminal.getScrollInvariantLine(row: entry.row) === line
    else { return nil }
    return entry.row
  }

  /// Texto del buffer normal; las filas que continúan una línea partida se unen sin salto.
  public func text(rows: Range<Int>) -> String {
    let snapshot = terminal.contentSnapshot(region: .rows(rows), buffer: .normal)
    var text = ""
    for (index, row) in snapshot.rows.enumerated() {
      if index > 0 && !row.isWrapped { text.append("\n") }
      text.append(row.text)
    }
    return text
  }

  /// Lo visible ahora, en las mismas filas que las anclas.
  public func viewportSnapshot(cellSize: CGSize) -> ViewportSnapshot {
    let snapshot = terminal.contentSnapshot(region: .viewport, buffer: .active)
    return ViewportSnapshot(
      topRow: snapshot.capturedRange.lowerBound, rows: snapshot.dimensions.rows,
      columns: snapshot.dimensions.cols, cellSize: cellSize,
      occupiedRows: IndexSet(snapshot.rows.filter { !$0.text.isEmpty }.map(\.absoluteRow)),
      cursor: GridPosition(col: snapshot.cursorColumn, row: snapshot.cursorRow))
  }

  /// `TerminalView.scrollTo(row:)` cuenta desde la primera línea retenida, no desde la primera
  /// que existió.
  public func scrollIndex(forRow row: Int) -> Int {
    max(0, row - terminal.buffer.totalLinesTrimmed)
  }

  // MARK: Inserción

  /// Comprobación y escritura en una sola operación síncrona: entre ambas no puede llegar una
  /// marca que cambie el prompt (A8, A11). Nunca añade retorno de carro.
  public func insertIntoPrompt(
    _ text: String, token: InsertionToken, send: ([UInt8]) -> Void
  ) -> InsertResult {
    guard !hasPendingWork, token.session == session,
      token.promptGeneration == blocks.promptGeneration
    else { return .stale }
    guard !terminal.isCurrentBufferAlternate, blocks.isCurrent(token) else { return .notAtPrompt }
    switch PromptInsertion.validate(text) {
    case .failure(let rejection): return .unsafe(rejection)
    case .success(let validated):
      let bytes = Array(validated.utf8)
      send(terminal.bracketedPasteMode ? Self.bracketedStart + bytes + Self.bracketedEnd : bytes)
      return .inserted
    }
  }

  private static let bracketedStart = Array("\u{1b}[200~".utf8)
  private static let bracketedEnd = Array("\u{1b}[201~".utf8)

  // MARK: Handlers (dentro del feed, con el lock del terminal tomado)

  private func receive(_ payload: ArraySlice<UInt8>) {
    guard let nonce, let event = OSCParser.parse(payload: payload, nonce: nonce) else {
      rejectedInFeed += 1
      return
    }
    if event == .promptStarted { sawAuthenticatedPrompt = true }
    noteTrimming()
    enqueue(.event(event, captureCursorAnchor()))
  }

  private func receiveTitle(code: Int, payload: ArraySlice<UInt8>) {
    // 1 es el título del icono, que macOS no muestra; se registra para anular el de SwiftTerm.
    guard code != 1 else { return }
    onTitleChange?(TitleSanitizer.clean(String(decoding: payload, as: UTF8.self)))
  }

  private func captureCursorAnchor() -> RowAnchor {
    let row = terminal.buffer.totalLinesTrimmed + liveTopIndex() + terminal.getCursorLocation().y
    lastAnchorID += 1
    anchors[lastAnchorID] = AnchoredLine(line: terminal.getScrollInvariantLine(row: row), row: row)
    anchorsAddedSinceCompaction = true
    return RowAnchor(id: lastAnchorID)
  }

  /// Índice de la primera fila de la pantalla viva. SwiftTerm 1.99.3 no publica `yBase`, pero el
  /// buffer siempre guarda `yBase + rows` líneas: se obtiene del número de líneas.
  private func liveTopIndex() -> Int {
    let trimmed = terminal.buffer.totalLinesTrimmed
    let viewportTop = terminal.buffer.yDisp
    func exists(_ index: Int) -> Bool {
      terminal.getScrollInvariantLine(row: trimmed + index) != nil
    }
    // Sin desplazamiento hacia atrás, la vista es la pantalla viva.
    var known = viewportTop + terminal.rows
    guard exists(known) else { return viewportTop }
    var step = terminal.rows
    while exists(known + step) {
      known += step
      step *= 2
    }
    var missing = known + step
    while missing - known > 1 {
      let middle = known + (missing - known) / 2
      if exists(middle) { known = middle } else { missing = middle }
    }
    return missing - terminal.rows
  }

  // MARK: Cola

  private func enqueue(_ item: Item) {
    if pending.count - nextPending >= Self.maxPending { overflow() }
    enqueueScreenIfChanged()
    pending.append(item)
  }

  private func enqueueScreenIfChanged() {
    let alternate = terminal.isCurrentBufferAlternate
    guard alternate != queuedAlternate else { return }
    queuedAlternate = alternate
    if pending.count - nextPending >= Self.maxPending { overflow() }
    pending.append(.screen(alternate: alternate))
  }

  /// Sin memoria para lo pendiente ya no se sabe qué marcas faltan: se tira todo y el tracker
  /// espera un prompt nuevo (A11).
  private func overflow() {
    logger.error(
      "7777 queue overflowed; dropped: \(self.pending.count - self.nextPending, privacy: .public)")
    discardPending()
    blocks.desynchronize()
  }

  private func discardPending() {
    pending.removeAll()
    nextPending = 0
    queuedAlternate = appliedAlternate
  }

  private func drainNow() {
    guard !drainScheduled, drainBatch() else { return }
    drainScheduled = true
    scheduleNextTurn { [weak self] in
      guard let self else { return }
      drainScheduled = false
      drainNow()
    }
  }

  /// Aplica hasta `batchSize` elementos. Un elemento sale de la cola después de aplicarse, así
  /// que una inserción pedida desde un callback del tracker sigue viendo trabajo pendiente.
  /// Devuelve si queda algo por aplicar.
  @discardableResult public func drainBatch() -> Bool {
    var applied = 0
    while applied < Self.batchSize, nextPending < pending.count {
      apply(pending[nextPending])
      nextPending += 1
      applied += 1
    }
    guard nextPending == pending.count else { return true }
    pending.removeAll(keepingCapacity: true)
    nextPending = 0
    pruneIfNeeded()
    compactAnchors()
    return false
  }

  private func apply(_ item: Item) {
    switch item {
    case .event(let event, let anchor):
      blocks.handle(event, anchor: anchor)
      if event == .promptStarted { dropBlocksOverwritten(by: anchor) }
      if case .aiRequest(let request) = event, let token = blocks.insertionToken() {
        onAIRequest?(request, token)
      }
    case .screen(let alternate):
      appliedAlternate = alternate
      blocks.setAlternateScreen(alternate)
    case .reset:
      blocks.reset()
    }
  }

  // MARK: Mantenimiento de anclas

  /// Una línea reciclada vuelve al final del buffer con el mismo objeto: se descarta en cuanto
  /// el recorte pasa su fila, antes de que un reflow pudiera reasignarle otra (A1).
  private func noteTrimming() {
    if !terminal.isCurrentBufferAlternate { normalBuffer = terminal.buffer }
    let trimmed = normalBuffer.totalLinesTrimmed
    guard trimmed != observedTrimmed else { return }
    if trimmed < observedTrimmed {
      // `CSI 3 J` o un reset vuelven a numerar desde 0: ninguna fila guardada es comparable.
      anchors.removeAll()
    } else {
      anchors = anchors.filter { $0.value.row >= trimmed }
    }
    observedTrimmed = trimmed
    needsPrune = true
  }

  private func pruneIfNeeded() {
    guard needsPrune, !terminal.isCurrentBufferAlternate else { return }
    needsPrune = false
    blocks.prune(resolve: resolve)
  }

  /// La salida solo avanza: un prompt nuevo en la fila de un bloque anterior, o por encima,
  /// significa que la pantalla se reescribió (`clear`, `CSI H`) y esas filas ya muestran otra cosa.
  /// El fin del bloque anterior sí comparte fila con el prompt siguiente, así que se compara el
  /// prompt de cada bloque.
  private func dropBlocksOverwritten(by prompt: RowAnchor) {
    guard let promptRow = resolve(prompt) else { return }
    blocks.prune { anchor in
      guard let row = resolve(anchor) else { return nil }
      return anchor == prompt || row < promptRow ? row : nil
    }
  }

  private func rebaseline() {
    noteTrimming()
    var rowsByLine: [ObjectIdentifier: Int] = [:]
    var row = terminal.buffer.totalLinesTrimmed
    while let line = terminal.getScrollInvariantLine(row: row) {
      rowsByLine[ObjectIdentifier(line)] = row
      row += 1
    }
    anchors = anchors.compactMapValues { entry in
      guard let line = entry.line, let row = rowsByLine[ObjectIdentifier(line)] else { return nil }
      return AnchoredLine(line: line, row: row)
    }
    anchoredGeometry = (terminal.cols, terminal.rows)
    needsPrune = true
  }

  /// Con la cola vacía, solo hacen falta las anclas que guardan los bloques.
  private func compactAnchors() {
    guard anchorsAddedSinceCompaction else { return }
    anchorsAddedSinceCompaction = false
    var referenced = Set<UInt64>()
    for block in blocks.blocks {
      referenced.insert(block.promptAnchor.id)
      if let output = block.outputAnchor { referenced.insert(output.id) }
      if let end = block.endAnchor { referenced.insert(end.id) }
    }
    anchors = anchors.filter { referenced.contains($0.key) }
  }
}
