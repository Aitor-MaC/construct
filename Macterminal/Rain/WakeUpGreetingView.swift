import AppKit
import MacterminalCore

/// "Wake up, Neo…": atenúa el historial al 8 % y teclea el saludo según `WakeUpTimeline`.
/// Cualquier tecla lo salta sin consumirla (llega al shell) y la vista nunca toma el foco ni
/// recibe clics. `onDismiss` se llama una vez, al terminar de desaparecer; se muestra en cada
/// ventana o pestaña nueva (lo decide `Workspace.makePane`).
final class WakeUpGreetingView: NSView {
  /// El historial queda visible al 8 %: `bg` al 92 % por encima.
  static let historyAlpha = 0.08
  private static let dimIn: TimeInterval = 0.18
  private static let inset: CGFloat = 16
  private static let lineHeight: CGFloat = 22

  private let onDismiss: () -> Void
  private let reduceMotion: Bool
  private let timeline: WakeUpTimeline
  private let label = NSTextField(labelWithString: "")
  private var keyMonitor: Any?
  private var run: Task<Void, Never>?
  private var dismissed = false
  private var finished = false

  init(
    givenName: String?,
    reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
    onDismiss: @escaping () -> Void
  ) {
    self.onDismiss = onDismiss
    self.reduceMotion = reduceMotion
    timeline = WakeUpTimeline(givenName: givenName, reduceMotion: reduceMotion)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor =
      MatrixTheme.nsColor(MatrixPalette.bg, alpha: 1 - Self.historyAlpha).cgColor
    setAccessibilityElement(false)
    label.translatesAutoresizingMaskIntoConstraints = false
    label.refusesFirstResponder = true
    label.maximumNumberOfLines = 0
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
      label.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.inset),
    ])
    alphaValue = 0
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  /// Nombre de pila del usuario de la cuenta; `nil` si el sistema no lo da. Es el respaldo de
  /// `greeting-name` en `GreetingName.resolve`.
  static func currentGivenName() -> String? {
    PersonNameComponentsFormatter().personNameComponents(from: NSFullUserName())?.givenName
  }

  override var acceptsFirstResponder: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window == nil {
      stop()
      // Sacada de la ventana durante el fundido: la tarea se canceló, pero el panel debe saber
      // que el saludo terminó.
      if dismissed { finish() }
    } else if run == nil, !dismissed {
      start()
    }
  }

  /// Salta el saludo: fundido de salida (instantáneo con Reduce Motion) y `onDismiss`.
  func dismiss() {
    guard !dismissed else { return }
    dismissed = true
    stop()
    run = Task { [weak self] in await self?.fadeOutAndFinish() }
  }

  private func start() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      // Solo las teclas de esta ventana; el evento sigue su camino hasta el shell.
      MainActor.assumeIsolated {
        if let self, event.window === self.window { self.dismiss() }
      }
      return event
    }
    animateAlpha(to: 1, duration: reduceMotion ? 0 : Self.dimIn)
    run = Task { [weak self] in await self?.play() }
  }

  private func stop() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    keyMonitor = nil
    run?.cancel()
    run = nil
  }

  private func play() async {
    let clock = ContinuousClock()
    let start = clock.now
    var elapsed = Duration.zero
    show(timeline.phase(at: elapsed))
    while let next = timeline.nextChange(after: elapsed) {
      do {
        try await clock.sleep(until: start + next)
      } catch {
        return
      }
      elapsed = next
      let phase = timeline.phase(at: elapsed)
      if case .fadingOut = phase {
        dismiss()
        return
      }
      show(phase)
    }
    dismiss()
  }

  private func fadeOutAndFinish() async {
    let fade = reduceMotion ? Duration.zero : WakeUpTimeline.fadeOut
    animateAlpha(to: 0, duration: fade / .seconds(1))
    do {
      try await ContinuousClock().sleep(for: fade)
    } catch {
      return
    }
    finish()
  }

  /// `onDismiss` una sola vez, acabe el fundido o salga la vista de la ventana a mitad.
  private func finish() {
    guard !finished else { return }
    finished = true
    onDismiss()
  }

  private func show(_ phase: WakeUpTimeline.Phase) {
    guard case .showing(let lines) = phase else { return }
    label.attributedStringValue = Self.styled(lines.joined(separator: "\n"))
  }

  private func animateAlpha(to target: CGFloat, duration: TimeInterval) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      animator().alphaValue = target
    }
  }

  /// Krypton Medium 15/22 en fósforo con el glow de acento de Inmersivo (mock F1).
  private static func styled(_ text: String) -> NSAttributedString {
    let profile = Intensity.inmersivo.profile
    let font =
      NSFont(name: "MonaspaceKryptonNF-Medium", size: 15)
      ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .medium)
    let glow = NSShadow()
    glow.shadowColor = MatrixTheme.nsColor(MatrixPalette.ph400, alpha: profile.accentGlowAlpha)
    glow.shadowBlurRadius = profile.accentGlowRadius
    glow.shadowOffset = .zero
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    return NSAttributedString(
      string: text,
      attributes: [
        .font: font, .foregroundColor: MatrixTheme.nsColor(MatrixPalette.ph400), .shadow: glow,
        .paragraphStyle: paragraph,
      ])
  }
}
