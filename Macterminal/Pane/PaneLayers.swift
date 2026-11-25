import AppKit
import MacterminalCore
import MacterminalTerminal
import SwiftTerm
import SwiftUI

/// Capas de un panel, de abajo arriba: lluvia (+ cursor de fósforo) → fondos de bloque →
/// terminal → controles de bloque → CRT → saludo o pregunta del nombre → barra ⌘F → tarjeta de la IA. El `bg` y su
/// opacidad son del contenedor de la ventana (A7); aquí todo es transparente. Las capas de
/// encima del texto son subvistas de la terminal para que la barra ⌘F, que T13 monta dentro de
/// ella, quede por encima de los controles y del CRT. Los toasts son de la ventana
/// (`WindowToastLayer`).
@MainActor final class PaneLayers {
  let blockState = BlockOverlayState()
  private(set) var findBar: MatrixFindBar?

  private let rain: RainCanvasView
  private let crt: CRTOverlayView
  private var backdrop: NSHostingView<BlocksBackdropView>?
  private var overlay: BlocksOverlayHostingView?
  private let suggestions: SuggestionFlow
  private let firstCommand: FirstCommandFlag
  private var card: NSHostingView<SuggestionCardLayer>?
  private weak var terminal: TerminalView?
  private var greeting: WakeUpGreetingView?
  private var onboarding: NameOnboardingHost?
  private var typingReset: Task<Void, Never>?
  private var refreshScheduled = false
  /// Agrupa salida, scroll y redimensionado en un redibujo por fotograma como mucho.
  private static let refreshInterval = Duration.milliseconds(16)

  /// `viewport` es la geometría inicial de la rejilla; `nil` si SwiftTerm no entregó su
  /// `Terminal` (el panel muestra el error de arranque y la lluvia no llega a correr).
  /// "Insertar" de la tarjeta; lo pone el panel, que es quien escribe en el PTY.
  var onInsert: ((CommandSuggestion) -> Void)?

  init(
    intensity: Intensity, viewport: ViewportSnapshot?, suggestions: SuggestionFlow,
    firstCommand: FirstCommandFlag
  ) {
    self.suggestions = suggestions
    self.firstCommand = firstCommand
    rain = RainCanvasView(
      intensity: intensity, cellSize: viewport?.cellSize ?? CGSize(width: 1, height: 1),
      rows: max(1, viewport?.rows ?? 1), columns: max(1, viewport?.columns ?? 1))
    crt = CRTOverlayView(intensity: intensity)
  }

  /// Monta las capas alrededor de `terminal`, que ya está dentro de `container`.
  func install(in container: NSView, terminal: TerminalView, pane: TerminalPaneController) {
    self.terminal = terminal
    fill(container, with: rain, below: terminal)
    if let viewport = pane.viewportSnapshot() {
      let backdrop = NSHostingView(rootView: backdropView(pane, viewport))
      let overlay = BlocksOverlayHostingView(rootView: overlayView(pane, viewport))
      backdrop.sizingOptions = []
      overlay.sizingOptions = []
      fill(container, with: backdrop, below: terminal)
      fill(terminal, with: overlay)
      self.backdrop = backdrop
      self.overlay = overlay
    }
    fill(terminal, with: crt)
    findBar = MatrixFindBar.install(on: terminal)
    installCard(in: terminal)
  }

  // MARK: Fotograma

  /// Pide un redibujo de lluvia y bloques; varios avisos en el mismo fotograma cuentan como uno.
  func setNeedsRefresh(_ pane: TerminalPaneController) {
    guard !refreshScheduled else { return }
    refreshScheduled = true
    Task { [weak self, weak pane] in
      do { try await Task.sleep(for: Self.refreshInterval) } catch { return }
      guard let self else { return }
      self.refreshScheduled = false
      if let pane { self.refresh(pane) }
    }
  }

  /// A3: una sola instantánea por fotograma; la lluvia la recibe en filas de la vista y los
  /// bloques en absolutas.
  private func refresh(_ pane: TerminalPaneController) {
    guard let viewport = pane.viewportSnapshot() else { return }
    if viewport.cellSize.width > 0, viewport.cellSize.height > 0 { rain.cellSize = viewport.cellSize }
    rain.rows = max(1, viewport.rows)
    rain.columns = max(1, viewport.columns)
    rain.textRows = viewport.viewportOccupiedRows()
    rain.cursorLayer.cursor = viewport.viewportCursor()
    backdrop?.rootView = backdropView(pane, viewport)
    overlay?.rootView = overlayView(pane, viewport)
  }

  private func backdropView(_ pane: TerminalPaneController, _ viewport: ViewportSnapshot)
    -> BlocksBackdropView
  {
    BlocksBackdropView(
      tracker: pane.blocks, state: blockState, viewport: viewport, resolve: pane.resolve)
  }

  private func overlayView(_ pane: TerminalPaneController, _ viewport: ViewportSnapshot)
    -> BlocksOverlayView
  {
    BlocksOverlayView(
      tracker: pane.blocks, state: blockState, viewport: viewport, resolve: pane.resolve,
      textProvider: pane.text(rows:),
      insertIntoPrompt: { [weak pane] text, token in
        pane?.insertIntoPrompt(text, token: token) ?? .stale
      },
      integrationAvailable: pane.integrationAvailable,
      openPalette: { ActionRegistry.shared.perform(.commandPalette) },
      firstCommand: firstCommand)
  }

  // MARK: Estado

  func apply(intensity: Intensity) {
    rain.intensity = intensity
    crt.intensity = intensity
  }

  func apply(runState: RainRunState, reduceMotion: Bool, increaseContrast: Bool) {
    rain.reduceMotion = reduceMotion
    rain.increaseContrast = increaseContrast
    crt.reduceMotion = reduceMotion
    crt.increaseContrast = increaseContrast
    rain.runState = runState
  }

  /// La lluvia baja de intensidad mientras se teclea y vuelve tras `typingIdleDelay` sin teclas.
  func noteKeyInput(intensity: Intensity) {
    rain.typing = TypingState(idleSince: .zero)
    typingReset?.cancel()
    let delay = intensity.profile.typingIdleDelay
    typingReset = Task { [weak self] in
      do { try await Task.sleep(for: delay) } catch { return }
      self?.rain.typing = TypingState(idleSince: delay)
    }
  }

  // MARK: Saludo y tarjeta

  /// "Wake up, …": encima del texto y del CRT, debajo de la barra ⌘F.
  func showGreeting(givenName: String?) {
    guard let terminal, greeting == nil else { return }
    let view = WakeUpGreetingView(givenName: givenName) { [weak self] in
      self?.greeting?.removeFromSuperview()
      self?.greeting = nil
      self?.updateBlockLayersVisibility()
    }
    greeting = view
    updateBlockLayersVisibility()
    view.frame = terminal.bounds
    view.autoresizingMask = [.width, .height]
    terminal.addSubview(view, positioned: .above, relativeTo: crt)
  }

  /// Pregunta del nombre (primer arranque), en el mismo hueco que el saludo. Se queda con el
  /// foco mientras está visible, así que ninguna tecla llega al PTY; al cerrarse, el foco vuelve
  /// a la terminal. `onContinue` devuelve `false` si no se pudo guardar y el overlay sigue.
  func showNameOnboarding(onContinue: @escaping (String) -> Bool, onSkip: @escaping () -> Void) {
    guard let terminal, onboarding == nil else { return }
    let view = NameOnboardingHost(
      rootView: NameOnboardingView(
        onContinue: { [weak self] name in
          guard onContinue(name) else { return false }
          self?.dismissNameOnboarding()
          return true
        },
        onSkip: { [weak self] in
          guard self?.onboarding != nil else { return }
          self?.dismissNameOnboarding()
          onSkip()
        }))
    view.sizingOptions = []
    onboarding = view
    updateBlockLayersVisibility()
    view.frame = terminal.bounds
    view.autoresizingMask = [.width, .height]
    terminal.addSubview(view, positioned: .above, relativeTo: crt)
  }

  /// Quita el overlay (que tenía el foco, ver `NameOnboardingHost`) y devuelve el foco a la
  /// terminal.
  private func dismissNameOnboarding() {
    guard let onboarding else { return }
    self.onboarding = nil
    let window = onboarding.window
    onboarding.removeFromSuperview()
    updateBlockLayersVisibility()
    if let terminal { window?.makeFirstResponder(terminal) }
  }

  /// El estado vacío de los bloques ("Sesión nueva…", "Abrir paleta") se leería bajo el velo
  /// de la pregunta o del saludo, solapado con su texto; la lluvia sí debe verse, así que solo
  /// se ocultan las capas de bloques mientras alguno de los dos está en pantalla.
  private func updateBlockLayersVisibility() {
    let hidden = onboarding != nil || greeting != nil
    backdrop?.isHidden = hidden
    overlay?.isHidden = hidden
  }

  /// Muestra u oculta la tarjeta según el flujo; con tarjeta, el foco va a sus botones, y al
  /// cerrarse vuelve a la terminal.
  func cardDidChange(visible: Bool) {
    guard let card, card.isHidden == visible else { return }
    card.isHidden = !visible
    guard let window = card.window, let terminal else { return }
    if visible {
      window.makeFirstResponder(card)
    } else if let responder = window.firstResponder as? NSView, responder.isDescendant(of: card) {
      window.makeFirstResponder(terminal)
    }
  }

  func stop() {
    typingReset?.cancel()
    typingReset = nil
    rain.runState = .hidden
    greeting?.dismiss()
    dismissNameOnboarding()
  }

  private func installCard(in terminal: TerminalView) {
    let card = NSHostingView(
      rootView: SuggestionCardLayer(flow: suggestions) { [weak self] in self?.onInsert?($0) })
    self.card = card
    card.translatesAutoresizingMaskIntoConstraints = false
    card.isHidden = true
    terminal.addSubview(card)
    NSLayoutConstraint.activate([
      card.leadingAnchor.constraint(equalTo: terminal.leadingAnchor, constant: 16),
      card.trailingAnchor.constraint(lessThanOrEqualTo: terminal.trailingAnchor, constant: -16),
      card.bottomAnchor.constraint(equalTo: terminal.bottomAnchor, constant: -16),
      card.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
    ])
  }

  private func fill(_ parent: NSView, with child: NSView, below sibling: NSView? = nil) {
    child.frame = parent.bounds
    child.autoresizingMask = [.width, .height]
    if let sibling {
      parent.addSubview(child, positioned: .below, relativeTo: sibling)
    } else {
      parent.addSubview(child)
    }
  }
}

/// La tarjeta de la IA del panel, alimentada por su `SuggestionFlow`.
struct SuggestionCardLayer: View {
  let flow: SuggestionFlow
  let onInsert: (CommandSuggestion) -> Void

  var body: some View {
    if let state = flow.card {
      SuggestionCardView(state: state, onInsert: onInsert, onCancel: flow.cancel)
    }
  }
}
