import AppKit
import MacterminalCore
import MacterminalTerminal
import OSLog

/// Composición de la app: la única instancia de `ConfigStore`, `HistoryStore` y
/// `CommandSuggester`, la fábrica de paneles, la ventana Quake, la paleta y el registro de todas
/// las acciones. La crea `AppDelegate` y vive lo que dura la app.
@MainActor final class Workspace {
  /// Se contestó la pregunta del nombre (también con "Ahora no"); el nombre vive en el config.
  static let onboardingCompletedKey = "onboardingCompleted"

  let configURL: URL
  let configStore: ConfigStore
  private let history: HistoryStore
  private let suggester = CommandSuggester()
  private let registry: ActionRegistry
  private let signals = RainSignals()
  private let defaults: UserDefaults
  /// Uno para toda la app: el estado vacío desaparece de todos los paneles a la vez.
  private let firstCommand: FirstCommandFlag
  /// Paneles vivos, para aplicar la config en caliente; los suelta su contenedor al cerrarse.
  private let panes = NSHashTable<TerminalPaneController>.weakObjects()
  private var quake: QuakeWindowController?
  private var palette: PaletteController?
  /// El primer panel que se cree pregunta el nombre (primer arranque, `OnboardingPolicy`).
  private var asksName = false
  /// Recibe de `AppCommands` la acción de SwiftUI que abre la escena `Settings`.
  let settingsOpener = SettingsOpener()
  private let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "history")

  init(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    registry: ActionRegistry = .shared, defaults: UserDefaults = .standard
  ) {
    self.registry = registry
    self.defaults = defaults
    firstCommand = FirstCommandFlag(defaults: defaults)
    configURL = home.appending(path: ".config/macterminal/config")
    configStore = ConfigStore(fileURL: configURL)
    let support = URL.applicationSupportDirectory.appending(path: "Macterminal/history.json")
    // `HistoryStore` ya registra el fallo (dominio y código); aquí solo se avisa al usuario.
    history = HistoryStore(
      fileURL: support,
      onError: { error in
        Task { @MainActor in ToastCenter.shared.show(error.localizedDescription) }
      })
  }

  /// Arranque: config vigilada, historial cargado, acciones registradas, atajo Quake y la
  /// primera ventana.
  func start() {
    configStore.onChange = { [weak self] in self?.apply($0) }
    configStore.onIssues = { Self.showIssues($0) }
    configStore.startWatching()
    Self.showIssues(configStore.issues)
    signals.onChange = { [weak self] in self?.refreshAllPanes() }
    signals.start()
    loadHistory()

    // `unowned`: `AppDelegate` guarda el `Workspace` hasta que termina el proceso, y las
    // ventanas y el registro que reciben estas fábricas nunca le sobreviven.
    let quake = QuakeWindowController(
      paneFactory: { [unowned self] cwd, _ in
        // Quake hereda el directorio del panel con foco en el momento de abrirse. Sin saludo:
        // es la ventana rápida y se abre y cierra a menudo.
        makePane(cwd: cwd ?? registry.context.focusedPane?.currentDirectory, greets: false)
      }, registry: registry)
    if let hotkey = configStore.config.quakeHotkey { quake.applyHotkey(hotkey) }
    self.quake = quake
    registerActions(quake: quake)
    asksName = OnboardingPolicy.shouldAsk(
      hasConfiguredName: configStore.config.greetingName != nil,
      completedFlag: defaults.bool(forKey: Self.onboardingCompletedKey))
    openWindow(cwd: nil)
  }

  // MARK: Paneles

  /// `greets`: muestra el saludo «Wake up» al aparecer (ventana, pestaña o arranque; nunca splits).
  func makePane(cwd: URL?, greets: Bool) -> TerminalPaneController {
    let suggester = suggester
    let pane = TerminalPaneController(
      config: configStore.config, cwd: cwd,
      suggest: { try await suggester.suggest(for: $0, cwd: $1) }, signals: signals,
      firstCommand: firstCommand)
    let history = history
    // A9/S3: solo bloques con `recordInHistory` (el tracker ya filtra) y sin texto en los logs.
    pane.blocks.onBlockFinished = { block in
      guard let command = block.command else { return }
      let cwd = block.cwd
      Task { await history.record(command: command, cwd: cwd, at: Date()) }
    }
    pane.onDirectoryChange = { url in
      Task { await history.recordDirectory(url, at: Date()) }
    }
    if asksName {
      asksName = false
      pane.askNameOnAppear(nameRequest())
    } else if greets {
      pane.showWakeUpGreetingOnAppear()
    }
    panes.add(pane)
    return pane
  }

  /// `unowned`: ver `start()`.
  private var paneFactory: PaneFactory {
    { [unowned self] cwd, origin in makePane(cwd: cwd, greets: origin == .root) }
  }

  @discardableResult func openWindow(cwd: URL?) -> TerminalWindowController {
    let controller = TerminalWindowController(paneFactory: paneFactory, cwd: cwd, registry: registry)
    // Con `tabbingMode = .preferred` AppKit la uniría como pestaña; ⌘N es una ventana aparte.
    controller.window?.tabbingMode = .disallowed
    controller.showWindow(nil)
    controller.window?.tabbingMode = .preferred
    return controller
  }

  /// Guardar escribe `greeting-name` en el config (el panel muestra el saludo en ese momento);
  /// "Ahora no" solo recuerda que ya se preguntó.
  private func nameRequest() -> TerminalPaneController.NameRequest {
    let defaults = defaults
    return TerminalPaneController.NameRequest(
      save: { [weak self] name in
        guard let self, write(.greetingName, name) else { return false }
        defaults.set(true, forKey: Self.onboardingCompletedKey)
        return true
      },
      skip: { defaults.set(true, forKey: Self.onboardingCompletedKey) })
  }

  // MARK: Config en caliente (A4)

  /// Fuente, intensidad y opacidad a todos los paneles abiertos; las claves del prompt
  /// (`prompt*`, `autosuggest`) y `shell` las toma cada panel nuevo de `configStore.config`.
  private func apply(_ config: TerminalConfig) {
    for pane in panes.allObjects { pane.apply(config) }
    if let hotkey = config.quakeHotkey { quake?.applyHotkey(hotkey) }
  }

  private func refreshAllPanes() {
    for pane in panes.allObjects { pane.refreshEnvironment() }
  }

  private static func showIssues(_ issues: [ConfigIssue]) {
    guard let first = issues.first else { return }
    let detail = String(localized: "Line \(first.line): \(first.message)", comment: "Toast text for the first configuration warning: line number, then the description of the problem.")
    let text =
      issues.count == 1
      ? String(localized: "Configuration warning. \(detail)", comment: "Toast shown when the configuration file has one problem. The argument is the description of the problem.")
      : String(localized: "\(issues.count) configuration warnings. \(detail)", comment: "Toast shown when the configuration file has several problems; the first argument is the count, the second the description of the first problem.")
    ToastCenter.shared.show(text)
  }

  // MARK: Historial

  private func loadHistory() {
    let history = history
    Task {
      if let error = await history.load() { ToastCenter.shared.show(error.localizedDescription) }
    }
  }

  /// Guarda el historial pendiente en ≤ `limit`; un error se registra y no bloquea la salida.
  func flushHistory(limit: Duration = .seconds(1)) async {
    let history = history
    let logger = logger
    let saved = await TimeLimit.run(
      limit: limit,
      operation: {
        do {
          try await history.flush()
        } catch {
          let code = (error as NSError).code
          logger.error("Couldn't save the history on quit (code \(code, privacy: .public))")
        }
        return true
      }, onTimeout: { false })
    if !saved { logger.error("Saving the history on quit timed out") }
  }

  /// Cuelga todos los shells explícitamente: al salir de la app no hay `windowWillClose`.
  func terminateAllPanes() {
    signals.stop()
    configStore.stopWatching()
    for pane in panes.allObjects { pane.terminate() }
  }

  // MARK: Acciones

  private func registerActions(quake: QuakeWindowController) {
    TerminalWindowController.registerActions(in: registry, paneFactory: paneFactory, quake: quake)
    BlocksOverlayView.registerActions(in: registry) { $0.blockState }
    let palette = makePalette()
    self.palette = palette
    PaletteController.registerActions(in: registry, palette: palette)
    registry.register(.newWindow) { [weak self] _ in self?.openWindow(cwd: nil) }
    registry.register(.find, isEnabled: { $0.focusedPane?.findBar != nil }) {
      $0.focusedPane?.findBar?.open()
    }
    registry.register(.clearScreen, isEnabled: { $0.focusedPane != nil }) {
      $0.focusedPane?.clearScreen()
    }
    registry.register(.settings) { [settingsOpener] _ in settingsOpener.open() }
    registry.register(.reloadConfig) { [weak self] _ in
      self?.configStore.reload()
      ToastCenter.shared.show(String(localized: "Configuration reloaded", comment: "Toast shown after the configuration file was edited outside the app and applied."))
    }
    for intensity in Intensity.allCases {
      registry.register(.setIntensity(intensity)) { [weak self] _ in
        self?.write(.intensity, intensity.rawValue)
      }
    }
    let steps: [(TerminalAction, FontSizeStep.Change)] = [
      (.increaseFontSize, .increase), (.decreaseFontSize, .decrease), (.resetFontSize, .reset),
    ]
    for (action, change) in steps {
      registry.register(
        action,
        isEnabled: { [weak self] _ in
          self.map { FontSizeStep.apply(change, to: $0.configStore.config.fontSize) != nil } ?? false
        },
        handler: { [weak self] _ in
          guard let self,
            let size = FontSizeStep.apply(change, to: configStore.config.fontSize)
          else { return }
          write(.fontSize, FontSizeStep.configValue(size))
        })
    }
  }

  private func makePalette() -> PaletteController {
    let history = history
    let registry = registry
    return PaletteController(
      historyProvider: {
        (await history.recentCommands(limit: 2000), await history.recentDirectories(limit: 50))
      },
      canInsert: { registry.context.focusedPane?.currentToken != nil },
      perform: { result in
        switch result {
        case .action(let action):
          registry.perform(action)
          return nil
        case .insert(let text):
          // El token se toma en el momento de insertar (A8).
          guard let pane = registry.context.focusedPane, let token = pane.currentToken else {
            return .notAtPrompt
          }
          return pane.insertIntoPrompt(text, token: token)
        }
      },
      currentIntensity: { [weak self] in self?.configStore.config.intensity },
      registry: registry)
  }

  /// Todo cambio de ajuste pasa por el archivo (una sola fuente de verdad); el error, a toast.
  @discardableResult private func write(_ key: ConfigKey, _ value: String) -> Bool {
    do {
      try configStore.set(key, value)
      return true
    } catch {
      ToastCenter.shared.show(error.localizedDescription)
      return false
    }
  }
}
