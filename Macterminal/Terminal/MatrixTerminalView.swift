import AppKit
import MacterminalCore
import MacterminalTerminal
import OSLog
import SwiftTerm

/// `TerminalView` con un `LocalProcess` propio en lugar de `LocalProcessTerminalView`, cuyos
/// `clipboardCopy`/`clipboardRead`/`requestOpenLink` no se pueden sustituir (OSC 52 quedaría
/// activo). Toda la salida del shell entra por `dataReceived`, en el hilo principal, envuelta por
/// `OSCBridge.feed`.
final class MatrixTerminalView: TerminalView, TerminalViewDelegate, LocalProcessDelegate {
  var onProcessExit: ((Int32?) -> Void)?
  var onStartFailure: ((LocalProcessError) -> Void)?
  var onScroll: (() -> Void)?
  var onKeyInput: ((NSEvent) -> Void)?
  /// Tras cada tramo de salida ya aplicado al buffer; el panel agrupa el redibujo de sus capas.
  var onOutput: (() -> Void)?
  /// Tras cada cambio de filas o columnas (también los de fuente).
  var onResize: (() -> Void)?

  private(set) var bridge: OSCBridge?
  private var process: LocalProcess?
  /// SwiftTerm no publica el `Terminal` de la vista; llega como `source` en los callbacks
  /// del emulador. Solo se toca en el hilo principal, donde ocurren todos los `feed` y resize.
  private var emulator: Terminal?
  private var keyMonitor: Any?
  private let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "pty")

  init(frame: NSRect, blocks: BlockTracker) {
    super.init(frame: frame)
    terminalDelegate = self
    // CWE-200: DECRQCRA con rectángulos de 1×1 dejaría leer la pantalla carácter a carácter. El
    // valor por defecto de SwiftTerm es `true` en Debug, así que se fija para cualquier build.
    enableRectangularAreaChecksum = false
    process = LocalProcess(delegate: self, dispatchQueue: .main)
    // Ocultar y mostrar el cursor hace que el emulador llame a `hideCursor(source:)` con su
    // `Terminal`, sin cambiar nada visible.
    feed(text: "\u{1b}[?25l\u{1b}[?25h")
    guard let emulator else { return }
    bridge = OSCBridge(terminal: emulator, blocks: blocks) { work in
      Task { @MainActor in work() }
    }
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(frame:blocks:)") }

  var isProcessRunning: Bool { process?.running ?? false }

  // MARK: Aspecto

  func applyAppearance(fontFamily: String, fontSize: Double) {
    font = FontLoader.terminalFont(family: fontFamily, size: fontSize)
    installColors(MatrixPalette.ansi.map(\.terminalColor))
    nativeForegroundColor = MatrixTheme.nsColor(MatrixPalette.fg)
    // Transparente: el fondo y su opacidad los pone la composición del panel (T14). Los fondos
    // ANSI explícitos y la selección siguen opacos (A7).
    nativeBackgroundColor = .clear
    caretColor = MatrixTheme.nsColor(MatrixPalette.cursor)
    selectedTextBackgroundColor = MatrixTheme.nsColor(MatrixPalette.selectionBg)
    minimumContrastRatio = 4.5
    appearance = NSAppearance(named: .darkAqua)
  }

  // MARK: Proceso

  func start(_ plan: ShellLaunchPlan, in directory: URL) {
    process?.startProcess(
      executable: plan.executable, args: [], environment: plan.environmentList,
      execName: plan.execName, currentDirectory: directory.path(percentEncoded: false))
  }

  func hangUp() {
    guard let process else { return }
    ShellHangup.hangUp(process)
  }

  func sendToShell(_ bytes: [UInt8]) {
    process?.send(data: bytes[...])
  }

  nonisolated func dataReceived(slice: ArraySlice<UInt8>) {
    // Sin puente no se arranca ningún proceso (ver `TerminalPaneController.start`).
    MainActor.assumeIsolated {
      bridge?.feed { feed(byteArray: slice) }
      onOutput?()
    }
  }

  nonisolated func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
    MainActor.assumeIsolated { onProcessExit?(exitCode) }
  }

  nonisolated func processFailedToStart(_ source: LocalProcess, error: LocalProcessError) {
    MainActor.assumeIsolated { onStartFailure?(error) }
  }

  nonisolated func getWindowSize() -> winsize {
    let dimensions = terminalDimensions
    return winsize(
      ws_row: UInt16(clamping: dimensions.rows), ws_col: UInt16(clamping: dimensions.cols),
      ws_xpixel: 0, ws_ypixel: 0)
  }

  // MARK: Emulador (dentro del feed, con el lock del terminal tomado)

  nonisolated override func hideCursor(source: Terminal) {
    super.hideCursor(source: source)
    // `Terminal` no es Sendable, pero no cruza de hilo: este callback corre dentro del `feed`
    // del `init`, en el hilo principal, y la app solo alimenta y redimensiona en ese hilo.
    nonisolated(unsafe) let terminal = source
    MainActor.assumeIsolated {
      if emulator == nil { emulator = terminal }
    }
  }

  nonisolated override func bufferActivated(source: Terminal) {
    super.bufferActivated(source: source)
    MainActor.assumeIsolated { bridge?.bufferActivated() }
  }

  // MARK: TerminalViewDelegate

  /// S9: el PTY recibe filas y columnas en cada cambio, también los de fuente.
  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    var size = getWindowSize()
    _ = process?.updateWindowSize(&size)
    bridge?.terminalDidResize()
    onResize?()
  }

  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    process?.send(data: data)
  }

  func scrolled(source: TerminalView, position: Double) { onScroll?() }

  /// Los títulos llegan por el handler propio de `OSCBridge`, ya saneados.
  func setTerminalTitle(source: TerminalView, title: String) {}

  /// OSC 7 sin autenticar: el directorio sale solo de las marcas 7777.
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

  /// I1: solo con ⌘-clic y según `LinkPolicy`; nunca con la política por defecto de SwiftTerm.
  func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {
    guard NSApp.currentEvent?.modifierFlags.contains(.command) == true else { return }
    guard let url = URL(string: request.link) else { return rejectLink() }
    switch LinkPolicy.decide(url) {
    case .open: NSWorkspace.shared.open(url)
    case .revealInFinder: NSWorkspace.shared.activateFileViewerSelecting([url])
    case .reject: rejectLink()
    }
  }

  private func rejectLink() {
    ToastCenter.shared.show(String(localized: "This kind of link can’t be opened from the terminal.", comment: "Toast shown when the user Command-clicks a link whose scheme is blocked."))
  }

  /// B3: OSC 52 nunca escribe en el portapapeles.
  func clipboardCopy(source: TerminalView, content: Data) {
    logger.info("OSC 52 ignored; length: \(content.count, privacy: .public)")
  }

  /// B3: sin respuesta a `OSC 52 ; c ; ?`.
  func clipboardRead(source: TerminalView) -> Data? { nil }

  func kittyClipboardCapabilities(source: TerminalView) -> KittyClipboardCapabilities { [] }

  func kittyClipboardAvailableMimeTypes(source: TerminalView, location: KittyClipboardLocation)
    -> [String]?
  { nil }

  func kittyClipboardRead(
    source: TerminalView, location: KittyClipboardLocation, mimeType: String
  ) -> KittyClipboardReadResult? { nil }

  func kittyClipboardWrite(
    source: TerminalView, location: KittyClipboardLocation, content: KittyClipboardWriteContent
  ) -> KittyClipboardWriteResult { .unsupported }

  func kittyClipboardRequestPermission(
    source: TerminalView, request: KittyClipboardPermissionRequest
  ) -> KittyClipboardPermissionResult { .deny }

  func bell(source: TerminalView) { NSSound.beep() }

  func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

  // MARK: Teclado y pegado

  /// `keyDown` de `TerminalView` no es `open`: un monitor local ve la tecla antes que la vista
  /// y solo avisa si esta vista es la que tiene el foco.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let keyMonitor {
      NSEvent.removeMonitor(keyMonitor)
      self.keyMonitor = nil
    }
    guard window != nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if let self, event.window === window, window?.firstResponder === self { onKeyInput?(event) }
      return event
    }
  }

  /// SwiftTerm reintenta un pegado con `ESC [201~` como inseguro permitido; aquí no llega.
  override func paste(_ sender: Any) {
    pasteText(PasteSanitizer.clean(NSPasteboard.general.string(forType: .string) ?? ""))
  }
}
