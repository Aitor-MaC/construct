import AppKit
import MacterminalCore
import MacterminalTerminal
import OSLog
import SwiftTerm
import SwiftUI

/// Un panel = un PTY zsh de login + su `BlockTracker`. Es la única puerta de escritura
/// programática en el PTY (`insertIntoPrompt`); el teclado y las respuestas del emulador van por
/// el transporte normal de SwiftTerm.
@MainActor
public final class TerminalPaneController: NSViewController {
  public let blocks = BlockTracker(wallClock: Date.init, monotonic: { ContinuousClock.now })
  public var onClose: (() -> Void)?
  /// El directorio de trabajo cambió por una marca `cwd` autenticada (OSC 7777, ya validada).
  public var onDirectoryChange: ((URL) -> Void)?
  /// Cambió algo que muestra la ventana: directorio o estado del proceso (título, icono proxy y
  /// punto verde). Los títulos OSC 0/2 nunca llegan aquí (I2).
  public var onStatusChange: (() -> Void)?
  /// Petición `# …` del prompt, ligada a su `InsertionToken` (A8).
  public let suggestions: SuggestionFlow

  /// Solo de marcas `cwd` autenticadas; hasta la primera, el directorio de arranque.
  public var currentDirectory: URL? { blocks.cwd ?? launchDirectory }
  public var isProcessRunning: Bool { matrixView.isProcessRunning }
  public var terminalView: TerminalView { matrixView }
  /// `false` si la shell no es zsh o no se pudo instalar la integración.
  public private(set) var integrationAvailable = false
  /// Token del prompt actual; `nil` si ahora no se puede escribir en él.
  public var currentToken: InsertionToken? { blocks.insertionToken() }
  /// Barra ⌘F del panel; `nil` hasta que se carga la vista.
  var findBar: MatrixFindBar? { layers.findBar }
  var blockState: BlockOverlayState { layers.blockState }

  private let matrixView: MatrixTerminalView
  private let container = NSView()
  private var errorHost: NSHostingView<ShellErrorView>?
  private var config: TerminalConfig
  private let launchDirectory: URL
  private let signals: RainSignals
  private let layers: PaneLayers
  private var wantsGreeting = false
  private var nameRequest: NameRequest?
  private var observationTasks: [Task<Void, Never>] = []
  private var startedAt: ContinuousClock.Instant?
  private var terminationRequested = false
  private let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "pty")

  /// `suggest` es la IA del panel (en la app, `CommandSuggester`); `signals`, las señales de la
  /// app que pausan la lluvia; `firstCommand`, el aviso de primer uso que comparten todos los
  /// paneles: lo activa el primer comando de cualquiera.
  init(
    config: TerminalConfig, cwd: URL?,
    suggest: @escaping SuggestionFlow.Suggest = { try await CommandSuggester().suggest(for: $0, cwd: $1) },
    signals: RainSignals = RainSignals(), firstCommand: FirstCommandFlag
  ) {
    self.config = config
    self.signals = signals
    let home = FileManager.default.homeDirectoryForCurrentUser
    launchDirectory = cwd.flatMap { $0.isFileURL && $0.path.hasPrefix("/") ? $0 : nil } ?? home
    matrixView = MatrixTerminalView(
      frame: NSRect(x: 0, y: 0, width: 960, height: 600), blocks: blocks)
    let suggestions = SuggestionFlow(
      suggest: suggest, isCurrent: { [blocks] in blocks.isCurrent($0) })
    self.suggestions = suggestions
    layers = PaneLayers(
      intensity: config.intensity,
      viewport: matrixView.bridge?.viewportSnapshot(cellSize: matrixView.caretFrame.size),
      suggestions: suggestions, firstCommand: firstCommand)
    blocks.onCommandStarted = { firstCommand.markSet() }
    super.init(nibName: nil, bundle: nil)
    title = "Construct"
    matrixView.applyAppearance(fontFamily: config.fontFamily, fontSize: config.fontSize)
    matrixView.onProcessExit = { [weak self] in self?.processExited(exitCode: $0) }
    matrixView.onStartFailure = { [weak self] _ in self?.processFailedToStart() }
    matrixView.bridge?.onAIRequest = { [weak self] text, token in
      guard let self else { return }
      suggestions.request(text, token: token, cwd: currentDirectory)
    }
    layers.onInsert = { [weak self] suggestion in self?.insertSuggestion(suggestion) }
    wireLayerRefresh()
    start(retryWithoutIntegration: false)
    observeDirectoryAndCard()
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init(config:cwd:)") }

  public override func loadView() {
    container.appearance = NSAppearance(named: .darkAqua)
    pin(matrixView, in: container)
    layers.install(in: container, terminal: matrixView, pane: self)
    view = container
  }

  public override func viewDidAppear() {
    super.viewDidAppear()
    if let window = view.window { WindowToastLayer.install(in: window) }
    refreshEnvironment()
    layers.setNeedsRefresh(self)
    if let nameRequest {
      self.nameRequest = nil
      layers.showNameOnboarding(
        onContinue: { [weak self] name in
          guard let self, nameRequest.save(name) else { return false }
          showGreeting()
          return true
        }, onSkip: nameRequest.skip)
    } else if wantsGreeting {
      wantsGreeting = false
      showGreeting()
    }
  }

  /// El nombre se resuelve en cada saludo: un cambio en caliente de `greeting-name` ya vale
  /// para el siguiente.
  private func showGreeting() {
    layers.showGreeting(
      givenName: GreetingName.resolve(
        configured: config.greetingName, systemGivenName: WakeUpGreetingView.currentGivenName()))
  }

  public override func viewDidLayout() {
    super.viewDidLayout()
    layers.setNeedsRefresh(self)
  }

  // MARK: Capas

  private func wireLayerRefresh() {
    matrixView.onOutput = { [weak self] in self.map { $0.layers.setNeedsRefresh($0) } }
    matrixView.onScroll = { [weak self] in self.map { $0.layers.setNeedsRefresh($0) } }
    matrixView.onResize = { [weak self] in self.map { $0.layers.setNeedsRefresh($0) } }
    matrixView.onKeyInput = { [weak self] event in
      guard let self else { return }
      layers.noteKeyInput(intensity: config.intensity)
      layers.blockState.noteKeyDown(withCommand: event.modifierFlags.contains(.command))
    }
  }

  /// Directorio (historial, título) y tarjeta de la IA siguen al estado observable.
  private func observeDirectoryAndCard() {
    let blocks = blocks
    let suggestions = suggestions
    observationTasks.append(Task { [weak self] in
      for await cwd in Observations({ blocks.cwd }) {
        guard let self else { return }
        if let cwd { onDirectoryChange?(cwd) }
        onStatusChange?()
      }
    })
    observationTasks.append(Task { [weak self] in
      for await visible in Observations({ suggestions.card != nil }) {
        guard let self else { return }
        layers.cardDidChange(visible: visible)
      }
    })
  }

  private func insertSuggestion(_ suggestion: CommandSuggestion) {
    let result = suggestions.insert(suggestion) { insertIntoPrompt($0, token: $1) }
    if let message = SuggestionFlow.failureMessage(for: result) { ToastCenter.shared.show(message) }
  }

  /// Lluvia, CRT y opacidad del fondo según la ventana y las señales de la app. Aumentar
  /// contraste fuerza el fondo opaco (A7).
  func refreshEnvironment() {
    let window = viewIfLoaded?.window
    let state = RainPausePolicy.state(
      windowOccluded: !(window?.occlusionState.contains(.visible) ?? false),
      windowActive: window?.isKeyWindow ?? false, appActive: signals.appActive,
      lowPower: signals.lowPower, reduceMotion: signals.reduceMotion,
      increaseContrast: signals.increaseContrast, intensity: config.intensity,
      fullScreenOnPower: (window?.styleMask.contains(.fullScreen) ?? false) && signals.onPower)
    layers.apply(
      runState: terminationRequested ? .hidden : state, reduceMotion: signals.reduceMotion,
      increaseContrast: signals.increaseContrast)
    (parent as? PaneContainerController)?.backgroundOpacity =
      signals.increaseContrast ? 1 : config.backgroundOpacity
  }

  /// Saludo «Wake up» al aparecer el panel, en cualquier intensidad; la composición lo pide en
  /// cada ventana o pestaña nueva y al arrancar (no en splits ni en Quake).
  func showWakeUpGreetingOnAppear() {
    wantsGreeting = true
  }

  /// Qué hacer con la respuesta a la pregunta del nombre. `save` devuelve `false` si no se pudo
  /// guardar; si guarda, el panel muestra el saludo en ese momento, en cualquier intensidad.
  struct NameRequest {
    let save: (String) -> Bool
    let skip: () -> Void
  }

  /// Primer arranque: pregunta el nombre al aparecer, en lugar del saludo.
  func askNameOnAppear(_ request: NameRequest) {
    nameRequest = request
  }

  // MARK: Arranque

  private func start(retryWithoutIntegration: Bool) {
    guard let bridge = matrixView.bridge else {
      logger.error("SwiftTerm didn't hand over its Terminal; the shell isn't started")
      return showFailure(.exitedAtStartup(
        message: StartupFailurePolicy.message(exitCode: nil), canRetryWithoutIntegration: false))
    }
    let nonce = SessionNonce.random()
    let plan: ShellLaunchPlan
    do {
      plan = try ShellLaunchPlan.make(
        shell: config.shell, inherited: ProcessInfo.processInfo.environment, locale: .current,
        integration: integration(nonce: nonce, retryWithoutIntegration: retryWithoutIntegration))
    } catch {
      logger.error("Configured shell is missing or not executable")
      return showFailure(.shellNotFound(message: error.localizedDescription))
    }
    hideFailure()
    integrationAvailable = plan.integrationAvailable
    bridge.begin(session: SessionID(), nonce: plan.integrationAvailable ? nonce : nil)
    startedAt = ContinuousClock.now
    logger.info("Shell launch: \(plan.executable, privacy: .private)")
    matrixView.start(plan, in: launchDirectory)
  }

  /// `install` antes de cada arranque (I5): reescribe los scripts por si se borraron de /tmp.
  private func integration(nonce: SessionNonce, retryWithoutIntegration: Bool)
    -> ShellLaunchPlan.Integration?
  {
    guard ShellLaunchPlan.wantsIntegration(
      shell: config.shell, retryWithoutIntegration: retryWithoutIntegration)
    else { return nil }
    do {
      let zdotdir = try ZshIntegration.install(in: FileManager.default.temporaryDirectory)
      return ShellLaunchPlan.Integration(
        zdotdir: zdotdir,
        options: PromptOptions(
          prompt: config.prompt, autosuggest: config.autosuggest,
          userHost: config.promptUserHost, path: config.promptPath),
        nonce: nonce)
    } catch {
      // `install` ya registró el motivo; el shell arranca sin integración.
      ToastCenter.shared.show(error.localizedDescription)
      return nil
    }
  }

  private func processExited(exitCode: Int32?) {
    matrixView.bridge?.end()
    suggestions.cancel()
    onStatusChange?()
    logger.info("Shell exited; code: \(exitCode.map(String.init) ?? "unknown", privacy: .public)")
    guard !terminationRequested else { return }
    let uptime = startedAt.map { ContinuousClock.now - $0 } ?? .zero
    guard StartupFailurePolicy.keepsPaneOpen(
      integrationAvailable: integrationAvailable,
      sawAuthenticatedPrompt: matrixView.bridge?.sawAuthenticatedPrompt ?? false, uptime: uptime)
    else {
      terminationRequested = true
      onClose?()
      return
    }
    showFailure(.exitedAtStartup(
      message: StartupFailurePolicy.message(exitCode: exitCode),
      canRetryWithoutIntegration: integrationAvailable))
  }

  private func processFailedToStart() {
    matrixView.bridge?.end()
    logger.error("The shell couldn’t be started")
    showFailure(.exitedAtStartup(
      message: StartupFailurePolicy.message(exitCode: nil), canRetryWithoutIntegration: false))
  }

  private func showFailure(_ failure: ShellErrorView.Failure) {
    hideFailure()
    let host = NSHostingView(
      rootView: ShellErrorView(failure: failure) { [weak self] in
        self?.start(retryWithoutIntegration: true)
      })
    errorHost = host
    pin(host, in: container)
  }

  private func hideFailure() {
    errorHost?.removeFromSuperview()
    errorHost = nil
  }

  private func pin(_ child: NSView, in parent: NSView) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      child.topAnchor.constraint(equalTo: parent.topAnchor),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
  }

  // MARK: API del panel

  /// Cuelga el shell y su grupo; en ≤ 1 s no queda ningún hijo, sin esperar a `deinit`.
  public func terminate() {
    guard !terminationRequested else { return }
    terminationRequested = true
    suggestions.cancel()
    observationTasks.forEach { $0.cancel() }
    observationTasks.removeAll()
    layers.stop()
    matrixView.hangUp()
    matrixView.bridge?.end()
  }

  public func insertIntoPrompt(_ text: String, token: InsertionToken) -> InsertResult {
    guard let bridge = matrixView.bridge else { return .stale }
    return bridge.insertIntoPrompt(text, token: token) { matrixView.sendToShell($0) }
  }

  /// Fuente y colores al momento; `prompt`, `autosuggest` y `shell` en la siguiente sesión (A4).
  public func apply(_ config: TerminalConfig) {
    self.config = config
    matrixView.applyAppearance(fontFamily: config.fontFamily, fontSize: config.fontSize)
    layers.apply(intensity: config.intensity)
    refreshEnvironment()
    layers.setNeedsRefresh(self)
  }

  /// ⌘K: borra pantalla y scrollback; el reset de bloques va detrás de las marcas pendientes.
  /// En el prompt, Ctrl-L hace que zsh lo vuelva a dibujar arriba.
  public func clearScreen() {
    guard let bridge = matrixView.bridge else { return }
    // Con marcas sin aplicar (un C recién llegado) `isAtPrompt` puede estar desfasado y el Ctrl-L
    // iría al programa en marcha. En el prompt, el widget `clear-screen` de la integración
    // redibuja el prompt y emite un A nuevo.
    let wasAtPrompt = blocks.isAtPrompt && !bridge.hasPendingWork
    bridge.reset()
    bridge.feed { matrixView.feed(byteArray: Self.clearScreenAndScrollback[...]) }
    if wasAtPrompt { matrixView.sendToShell([0x0C]) }
  }

  private static let clearScreenAndScrollback = Array("\u{1b}[H\u{1b}[2J\u{1b}[3J".utf8)

  public func scroll(toRow row: Int) {
    guard let bridge = matrixView.bridge else { return }
    matrixView.scrollTo(row: bridge.scrollIndex(forRow: row))
  }

  public func text(rows: Range<Int>) -> String {
    matrixView.bridge?.text(rows: rows) ?? ""
  }

  public func resolve(_ anchor: RowAnchor) -> Int? {
    matrixView.bridge?.resolve(anchor)
  }

  /// `nil` solo si SwiftTerm no entregó su `Terminal` (el panel muestra el error de arranque).
  public func viewportSnapshot() -> ViewportSnapshot? {
    matrixView.bridge?.viewportSnapshot(cellSize: matrixView.caretFrame.size)
  }
}
