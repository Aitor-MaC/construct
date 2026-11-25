import Foundation
import Observation

/// Estado de bloques de un panel, alimentado solo por marcas 7777 autenticadas. T7 serializa las
/// llamadas en el mismo orden en que llegaron los eventos.
@MainActor @Observable public final class BlockTracker {
  public static let maxBlocks = 5000

  public private(set) var blocks: [CommandBlock] = []
  public private(set) var cwd: URL?
  public private(set) var isAtPrompt = false
  /// Sube en cada `promptStarted` y nunca se reinicia: un token de un prompt anterior no puede
  /// volver a coincidir, ni siquiera tras `reset` o `beginSession` (A8).
  public private(set) var promptGeneration: UInt64 = 0

  @ObservationIgnored public var onBlockFinished: ((CommandBlock) -> Void)?
  /// Cada marca C aceptada; con ella se recuerda que el usuario ya ejecutó su primer comando.
  @ObservationIgnored public var onCommandStarted: (() -> Void)?

  @ObservationIgnored private let wallClock: () -> Date
  @ObservationIgnored private let monotonic: () -> ContinuousClock.Instant
  private var session: SessionID?
  private var isAlternateScreen = false
  private var isDesynchronized = false

  public init(wallClock: @escaping () -> Date, monotonic: @escaping () -> ContinuousClock.Instant) {
    self.wallClock = wallClock
    self.monotonic = monotonic
  }

  // MARK: Ciclo de vida

  /// Arranque y reintento del shell. La pantalla alternativa no se toca: refleja el emulador y
  /// solo la cambia `setAlternateScreen`.
  public func beginSession(_ id: SessionID) {
    session = id
    blocks = []
    cwd = nil
    isAtPrompt = false
    isDesynchronized = false
  }

  public func endSession() {
    session = nil
    isAtPrompt = false
  }

  /// RIS o ⌘K: la pantalla se borra, pero el shell y su directorio siguen siendo los mismos.
  public func reset() {
    closeOpenBlock()
    blocks = []
    isAtPrompt = false
  }

  /// Llamado por T7 cuando desborda su cola (A11): ya no sabemos qué marcas se perdieron, así que
  /// se cierra lo que estaba en marcha sin código y se espera un prompt nuevo para volver a confiar.
  public func desynchronize() {
    closeOpenBlock()
    isAtPrompt = false
    isDesynchronized = true
  }

  public func setAlternateScreen(_ on: Bool) {
    isAlternateScreen = on
  }

  // MARK: Eventos

  public func handle(_ event: ShellEvent, anchor: RowAnchor) {
    guard session != nil else { return }
    if isDesynchronized {
      guard event == .promptStarted else { return }
      isDesynchronized = false
    }
    if case .directoryChanged(let url) = event {
      cwd = url
      return
    }
    guard !isAlternateScreen else { return }
    switch event {
    case .promptStarted: startPrompt(at: anchor)
    case .commandStarted(let command, let recordInHistory):
      startCommand(command, recordInHistory: recordInHistory, at: anchor)
    case .commandFinished(let exitCode): finishCommand(exitCode: exitCode, at: anchor)
    // B solo delimita la entrada (el bloque ya está en `editing` desde A) y `ai` lo enruta T7
    // comprobando `insertionToken()`: ninguno cambia los bloques.
    case .inputStarted, .aiRequest, .directoryChanged: break
    }
  }

  private func startPrompt(at anchor: RowAnchor) {
    closeOpenBlock()
    promptGeneration += 1
    blocks.append(CommandBlock(cwd: cwd, promptAnchor: anchor))
    if blocks.count > Self.maxBlocks {
      blocks.removeFirst(blocks.count - Self.maxBlocks)
    }
    isAtPrompt = true
  }

  private func startCommand(_ command: String?, recordInHistory: Bool, at anchor: RowAnchor) {
    guard let index = blocks.indices.last, blocks[index].state == .editing else { return }
    blocks[index].command = command
    blocks[index].recordInHistory = recordInHistory
    blocks[index].cwd = cwd
    blocks[index].outputAnchor = anchor
    blocks[index].startedAt = wallClock()
    blocks[index].startedInstant = monotonic()
    blocks[index].state = .running
    isAtPrompt = false
    onCommandStarted?()
  }

  private func finishCommand(exitCode: Int32?, at anchor: RowAnchor) {
    guard let index = blocks.indices.last, blocks[index].state == .running else { return }
    blocks[index].exitCode = exitCode
    blocks[index].endAnchor = anchor
    blocks[index].duration = blocks[index].startedInstant.map { monotonic() - $0 }
    blocks[index].state = .finished
    notifyFinished(blocks[index])
  }

  /// Un bloque en marcha sin D queda `finished` con `exitCode` y duración desconocidos (`nil`,
  /// nunca 0). Uno en `editing` no llegó a ejecutar nada (Intro vacío, Ctrl-C): se descarta.
  private func closeOpenBlock() {
    guard let index = blocks.indices.last else { return }
    switch blocks[index].state {
    case .editing:
      blocks.removeLast()
    case .running:
      blocks[index].state = .finished
      notifyFinished(blocks[index])
    case .finished:
      break
    }
  }

  private func notifyFinished(_ block: CommandBlock) {
    guard block.recordInHistory, block.command != nil else { return }
    onBlockFinished?(block)
  }

  // MARK: Filas

  /// Quita los bloques cuyo prompt ya no existe en el buffer (recorte de scrollback, reflow).
  public func prune(resolve: (RowAnchor) -> Int?) {
    blocks.removeAll { resolve($0.promptAnchor) == nil }
  }

  public func block(before row: Int, resolve: (RowAnchor) -> Int?) -> CommandBlock? {
    blocks.last { block in resolve(block.promptAnchor).map { $0 < row } ?? false }
  }

  public func block(after row: Int, resolve: (RowAnchor) -> Int?) -> CommandBlock? {
    blocks.first { block in resolve(block.promptAnchor).map { $0 > row } ?? false }
  }

  /// Usa la versión actual del bloque y exige prompt ≤ salida ≤ fin ≤ siguiente prompt: si el
  /// reflow deja anclas incoherentes se devuelve `nil` antes que filas de otro bloque (A1).
  public func outputRows(of block: CommandBlock, resolve: (RowAnchor) -> Int?) -> Range<Int>? {
    guard let index = blocks.firstIndex(where: { $0.id == block.id }) else { return nil }
    let current = blocks[index]
    guard let promptRow = resolve(current.promptAnchor),
      let outputRow = current.outputAnchor.flatMap(resolve),
      let endRow = current.endAnchor.flatMap(resolve),
      promptRow <= outputRow, outputRow <= endRow
    else { return nil }
    if index + 1 < blocks.count, let nextPrompt = resolve(blocks[index + 1].promptAnchor),
      endRow > nextPrompt
    {
      return nil
    }
    return outputRow..<endRow
  }

  // MARK: Inserción

  public func insertionToken() -> InsertionToken? {
    guard let session, canInsert else { return nil }
    return InsertionToken(session: session, promptGeneration: promptGeneration)
  }

  public func isCurrent(_ token: InsertionToken) -> Bool {
    canInsert && token.session == session && token.promptGeneration == promptGeneration
  }

  /// `reset`, `beginSession` y `desynchronize` dejan sin bloque `editing`; `endSession` quita la
  /// sesión. Así el token solo vale en el prompt para el que se emitió.
  private var canInsert: Bool {
    session != nil && !isAlternateScreen && !isDesynchronized && blocks.last?.state == .editing
  }

  // MARK: Accesibilidad

  public func accessibilityLabel(for block: CommandBlock) -> String {
    guard block.state != .editing else {
      return String(
        localized: "Prompt, waiting for a command", bundle: .localized,
        comment: "VoiceOver label of the block that holds the prompt.")
    }
    let command =
      block.command
      ?? String(
        localized: "Command without text", bundle: .localized,
        comment: "VoiceOver name of a block whose command is empty.")
    guard block.state == .finished else {
      return String(
        localized: "\(command), running", bundle: .localized,
        comment: "VoiceOver label of a running block; the placeholder is the command.")
    }
    let duration =
      block.duration.map {
        " "
          + String(
            localized: "in \(DurationFormat.spoken($0))", bundle: .localized,
            comment:
              "Appended to a finished block's VoiceOver label; the placeholder is a spoken duration such as “3 seconds”."
          )
      } ?? ""
    switch block.exitCode {
    case .none:
      return String(
        localized: "\(command), finished without an exit code", bundle: .localized,
        comment: "VoiceOver label of a finished block; the placeholder is the command.") + duration
    case 0:
      return String(
        localized: "\(command), succeeded", bundle: .localized,
        comment: "VoiceOver label of a finished block; the placeholder is the command.") + duration
    case .some(let code):
      return String(
        localized: "\(command), failed with code \(code)", bundle: .localized,
        comment:
          "VoiceOver label of a failed block; the placeholders are the command and the exit code.")
        + duration
    }
  }
}
