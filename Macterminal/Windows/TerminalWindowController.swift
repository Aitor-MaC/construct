import AppKit
import MacterminalCore

/// One native tab: a window joined to the others through `tabbingMode = .preferred`.
final class TerminalWindowController: NSWindowController, NSWindowDelegate {
  /// Open tabs keep themselves alive until their window closes.
  private static var openControllers: [ObjectIdentifier: TerminalWindowController] = [:]
  private static let tabbingIdentifier = "com.aitorgarcia.Macterminal.terminal"

  let panes: PaneContainerController
  private let paneFactory: PaneFactory
  private let registry: ActionRegistry
  private let activityIndicator = ProcessActivityIndicator()

  init(paneFactory: @escaping PaneFactory, cwd: URL? = nil, registry: ActionRegistry = .shared) {
    self.paneFactory = paneFactory
    self.registry = registry
    panes = PaneContainerController(paneFactory: paneFactory, cwd: cwd)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    window.tabbingMode = .preferred
    window.tabbingIdentifier = Self.tabbingIdentifier
    window.appearance = NSAppearance(named: .darkAqua)
    window.titlebarAppearsTransparent = true
    // Opacity belongs to the background layer alone, so the window itself is see-through.
    window.isOpaque = false
    window.backgroundColor = .clear
    window.isReleasedWhenClosed = false
    window.minSize = NSSize(width: 360, height: 220)
    window.contentViewController = panes
    window.setContentSize(NSSize(width: 960, height: 600))
    window.tab.accessoryView = activityIndicator
    super.init(window: window)
    window.delegate = self
    panes.trackFocus(in: window)
    panes.onChange = { [weak self] in self?.refreshChrome() }
    panes.onEmpty = { [weak self] in self?.window?.close() }
    Self.openControllers[ObjectIdentifier(self)] = self
    refreshChrome()
  }

  @available(*, unavailable) required init?(coder: NSCoder) {
    fatalError("Use init(paneFactory:cwd:registry:)")
  }

  override func showWindow(_ sender: Any?) {
    if window?.tabGroup?.windows.count ?? 1 == 1 { window?.center() }
    super.showWindow(sender)
    panes.focusFocusedPane()
  }

  /// Opens a tab next to this one, starting where the focused pane is.
  func openTab() {
    let controller = TerminalWindowController(
      paneFactory: paneFactory, cwd: panes.focusedPane?.currentDirectory, registry: registry)
    guard let window, let newWindow = controller.window else { return }
    window.addTabbedWindow(newWindow, ordered: .above)
    controller.showWindow(nil)
  }

  /// The "+" button of the native tab bar.
  override func newWindowForTab(_ sender: Any?) { openTab() }

  func windowDidBecomeKey(_ notification: Notification) { publishContext() }

  func windowWillClose(_ notification: Notification) {
    panes.terminateAll()
    if registry.context.window === window { registry.context = ActionContext() }
    Self.openControllers[ObjectIdentifier(self)] = nil
  }

  private func refreshChrome() {
    activityIndicator.isActive = panes.hasRunningProcess
    applyTitle(for: panes.focusedPane?.currentDirectory)
    if window?.isKeyWindow == true { publishContext() }
  }

  /// Only the pane's validated working directory reaches the title; OSC titles never do (I2).
  private func applyTitle(for directory: URL?) {
    guard let window else { return }
    guard let directory, directory.isFileURL, directory.path.hasPrefix("/") else {
      window.title = "Construct"
      window.representedURL = nil
      window.tab.title = "Construct"
      return
    }
    let path = (directory.path as NSString).abbreviatingWithTildeInPath
    window.title = "Construct — \(path)"
    window.representedURL = directory
    window.tab.title = path
  }

  private func publishContext() {
    registry.context = ActionContext(focusedPane: panes.focusedPane, window: window)
  }
}

extension TerminalWindowController {
  /// Window, tab, split and focus actions. T14 calls this once at launch.
  static func registerActions(
    in registry: ActionRegistry, paneFactory: @escaping PaneFactory, quake: QuakeWindowController
  ) {
    registry.register(.newTab) { context in
      if let controller = context.window?.windowController as? TerminalWindowController {
        controller.openTab()
      } else {
        TerminalWindowController(
          paneFactory: paneFactory, cwd: context.focusedPane?.currentDirectory, registry: registry
        ).showWindow(nil)
      }
    }
    registry.register(.closePane, isEnabled: { panes(in: $0) != nil }) { context in
      panes(in: context)?.closeFocusedPane()
    }
    registry.register(.nextTab, isEnabled: hasSeveralTabs) { $0.window?.selectNextTab(nil) }
    registry.register(.previousTab, isEnabled: hasSeveralTabs) {
      $0.window?.selectPreviousTab(nil)
    }
    registry.register(.splitVertical, isEnabled: { panes(in: $0) != nil }) {
      panes(in: $0)?.split(.vertical)
    }
    registry.register(.splitHorizontal, isEnabled: { panes(in: $0) != nil }) {
      panes(in: $0)?.split(.horizontal)
    }
    for direction in [Direction.left, .right, .up, .down] {
      registry.register(
        .focusPane(direction), isEnabled: { panes(in: $0)?.canMoveFocus(direction) == true }
      ) { panes(in: $0)?.moveFocus(direction) }
    }
    registry.register(.toggleQuake) { _ in quake.toggle() }
  }

  private static func panes(in context: ActionContext) -> PaneContainerController? {
    switch context.window?.windowController {
    case let controller as TerminalWindowController: controller.panes
    case let controller as QuakeWindowController: controller.panes
    default: nil
    }
  }

  private static func hasSeveralTabs(_ context: ActionContext) -> Bool {
    (context.window?.tabbedWindows?.count ?? 0) > 1
  }
}

/// Green dot in the tab while a shell process is alive (real state, not decoration).
private final class ProcessActivityIndicator: NSView {
  var isActive = false {
    didSet { dot.isHidden = !isActive; setAccessibilityElement(isActive) }
  }
  private let dot = NSView()

  init() {
    super.init(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
    dot.wantsLayer = true
    dot.layer?.backgroundColor = MatrixTheme.nsColor(MatrixPalette.ansi[2]).cgColor
    dot.layer?.cornerRadius = 3
    dot.translatesAutoresizingMaskIntoConstraints = false
    dot.isHidden = true
    addSubview(dot)
    NSLayoutConstraint.activate([
      widthAnchor.constraint(equalToConstant: 14),
      heightAnchor.constraint(equalToConstant: 14),
      dot.widthAnchor.constraint(equalToConstant: 6),
      dot.heightAnchor.constraint(equalToConstant: 6),
      dot.centerXAnchor.constraint(equalTo: centerXAnchor),
      dot.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityRole(.image)
    setAccessibilityLabel(String(localized: "Process running", comment: "VoiceOver label of the terminal window while a command is running."))
    setAccessibilityElement(false)
  }

  @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init()") }
}
