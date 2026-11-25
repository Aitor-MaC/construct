import AppKit
import MacterminalCore

/// Drop-down terminal anchored to the top of the screen under the pointer.
final class QuakeWindowController: NSWindowController, NSWindowDelegate {
  /// Fraction 0-1 of the screen's visible height.
  static let heightFraction = 0.4
  static let slideDuration: TimeInterval = 0.18
  private static let slideAnimationKey = "quakeSlide"

  private(set) var panes: PaneContainerController?
  private let paneFactory: PaneFactory
  private let registry: ActionRegistry
  private var hotkey: GlobalHotkey?
  private var isShown = false
  private var shownSlide: QuakeSlide?
  /// Lets a slide-out that finishes after a new slide-in leave the window on screen.
  private var transitionGeneration = 0
  private weak var previousApp: NSRunningApplication?

  init(paneFactory: @escaping PaneFactory, registry: ActionRegistry = .shared) {
    self.paneFactory = paneFactory
    self.registry = registry
    let panel = QuakePanel(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 400), styleMask: [.borderless],
      backing: .buffered, defer: true)
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = false
    super.init(window: panel)
    panel.delegate = self
  }

  @available(*, unavailable) required init?(coder: NSCoder) {
    fatalError("Use init(paneFactory:registry:)")
  }

  /// Registers or re-registers the global shortcut; failures surface as a toast, never a crash.
  func applyHotkey(_ shortcut: KeyShortcut) {
    do {
      if let hotkey {
        try hotkey.update(to: shortcut)
      } else {
        hotkey = try GlobalHotkey(shortcut: shortcut) { [weak self] in self?.toggle() }
      }
    } catch {
      ToastCenter.shared.show(error.localizedDescription)
    }
  }

  func toggle() {
    if isShown { slideOut() } else { slideIn() }
  }

  func windowDidBecomeKey(_ notification: Notification) { publishContext() }

  private func slideIn() {
    guard let window, let screen = Self.screenUnderPointer() else { return }
    isShown = true
    transitionGeneration += 1
    let panes = ensurePanes(in: window)
    let slide = QuakeSlide(visible: screen.visibleFrame, heightFraction: Self.heightFraction)
    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let frontmost = NSWorkspace.shared.frontmostApplication
    previousApp = frontmost == .current ? nil : frontmost
    shownSlide = slide
    window.setFrame(slide.frame, display: false)
    // A slide-out still running holds its hidden end state; without this, reopening with Reduce
    // Motion (no new animation to replace it) would show an empty panel.
    window.contentView?.layer?.removeAnimation(forKey: Self.slideAnimationKey)
    window.alphaValue = reduceMotion ? 1 : 0
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    panes.focusFocusedPane()
    guard !reduceMotion else { return }
    animate(window, contentFrom: slide.hiddenContentOffset, to: 0, alpha: 1, timing: .easeOut)
  }

  private func slideOut() {
    guard let window, let slide = shownSlide else { return }
    isShown = false
    transitionGeneration += 1
    let generation = transitionGeneration
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      finishSlideOut(generation: generation)
      return
    }
    animate(window, contentFrom: 0, to: slide.hiddenContentOffset, alpha: 0, timing: .easeIn) {
      [weak self] in
      self?.finishSlideOut(generation: generation)
    }
  }

  /// Slides the content layer inside the fixed window frame, which clips it, so the panel never
  /// draws outside the target screen. Only the presentation moves: the model stays at rest.
  private func animate(
    _ window: NSWindow, contentFrom start: CGFloat, to end: CGFloat, alpha: CGFloat,
    timing: CAMediaTimingFunctionName, completion: (@MainActor () -> Void)? = nil
  ) {
    guard let layer = window.contentView?.layer else { return }
    let slide = CABasicAnimation(keyPath: "transform.translation.y")
    slide.fromValue = start
    slide.toValue = end
    slide.duration = Self.slideDuration
    slide.timingFunction = CAMediaTimingFunction(name: timing)
    // Hold the end state until `finishSlideOut` orders the window out, avoiding a one-frame flash.
    slide.fillMode = .forwards
    slide.isRemovedOnCompletion = false
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.slideDuration
      context.timingFunction = CAMediaTimingFunction(name: timing)
      layer.add(slide, forKey: Self.slideAnimationKey)
      window.animator().alphaValue = alpha
    } completionHandler: {
      // AppKit runs animation completions on the main thread.
      MainActor.assumeIsolated { completion?() }
    }
  }

  private func finishSlideOut(generation: Int) {
    guard generation == transitionGeneration, let window else { return }
    window.orderOut(nil)
    window.contentView?.layer?.removeAnimation(forKey: Self.slideAnimationKey)
    window.alphaValue = 1
    previousApp?.activate()
    previousApp = nil
    if registry.context.window === window { registry.context = ActionContext() }
  }

  private func ensurePanes(in window: NSWindow) -> PaneContainerController {
    if let panes { return panes }
    let created = PaneContainerController(paneFactory: paneFactory, cwd: nil)
    created.onChange = { [weak self] in self?.publishContext() }
    // The last shell exited: hide now and start a fresh session on the next toggle.
    created.onEmpty = { [weak self] in
      guard let self else { return }
      self.panes = nil
      self.slideOut()
    }
    window.contentViewController = created
    // The slide animates this view's layer.
    created.view.wantsLayer = true
    created.trackFocus(in: window)
    panes = created
    return created
  }

  private func publishContext() {
    guard let window, window.isKeyWindow else { return }
    registry.context = ActionContext(focusedPane: panes?.focusedPane, window: window)
  }

  private static func screenUnderPointer() -> NSScreen? {
    let pointer = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
  }
}

/// Borderless panels refuse key status by default; the terminal needs the keyboard.
private final class QuakePanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}
