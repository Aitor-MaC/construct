import AppKit
import MacterminalCore

/// Hosts the split panes of one tab (or of the Quake panel): owns the `SplitTree`, the pane
/// controllers and which pane has focus. Divider dragging is plain `NSSplitView`.
final class PaneContainerController: NSViewController {
  /// Called after focus, pane count or process state changes, so the window can refresh chrome.
  var onChange: (() -> Void)?
  /// Called once the last pane has closed.
  var onEmpty: (() -> Void)?
  /// Alpha 0.5-1 of the window background layer, the only translucent surface (A7).
  var backgroundOpacity: Double = 1 {
    didSet {
      backgroundOpacity = backgroundOpacity.isFinite ? min(1, max(0.5, backgroundOpacity)) : 1
      applyBackground()
    }
  }

  private let paneFactory: PaneFactory
  private var tree: SplitTree
  private var panes: [PaneID: TerminalPaneController] = [:]
  private var focusedID: PaneID
  private let paneArea = NSView()
  private var firstResponderObservation: NSKeyValueObservation?
  private var needsLayoutRebuild = false

  init(paneFactory: @escaping PaneFactory, cwd: URL?) {
    let rootID = PaneID()
    self.paneFactory = paneFactory
    tree = SplitTree(root: rootID)
    focusedID = rootID
    super.init(nibName: nil, bundle: nil)
    attach(paneFactory(cwd, .root), as: rootID)
  }

  @available(*, unavailable) required init?(coder: NSCoder) {
    fatalError("Use init(paneFactory:cwd:)")
  }

  var focusedPane: TerminalPaneController? { panes[focusedID] }
  var hasRunningProcess: Bool { panes.values.contains { $0.isProcessRunning } }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    paneArea.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(paneArea)
    // The safe area keeps the panes below the transparent title bar and the tab bar.
    NSLayoutConstraint.activate([
      paneArea.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
      paneArea.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      paneArea.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      paneArea.trailingAnchor.constraint(equalTo: root.trailingAnchor),
    ])
    view = root
    applyBackground()
    rebuildLayout()
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard needsLayoutRebuild, !paneArea.bounds.isEmpty else { return }
    rebuildLayout()
    focusFocusedPane()
  }

  /// Tracks clicks into a pane so the title and actions follow the pane the user is typing in.
  func trackFocus(in window: NSWindow) {
    firstResponderObservation = window.observe(\.firstResponder) { [weak self] window, _ in
      // AppKit changes the first responder on the main thread only.
      MainActor.assumeIsolated { self?.firstResponderDidChange(window.firstResponder) }
    }
  }

  func focusFocusedPane() {
    guard let pane = focusedPane else { return }
    view.window?.makeFirstResponder(pane.view)
  }

  func split(_ axis: Axis) {
    let newID = PaneID()
    do {
      try tree.insert(at: focusedID, axis: axis, newID: newID)
    } catch {
      ToastCenter.shared.show(error.localizedDescription)
      return
    }
    attach(paneFactory(focusedPane?.currentDirectory, .split), as: newID)
    focusedID = newID
    rebuildLayout()
    focusFocusedPane()
    onChange?()
  }

  func closeFocusedPane() { closePane(focusedID) }

  func canMoveFocus(_ direction: Direction) -> Bool {
    tree.neighbor(of: focusedID, in: direction) != nil
  }

  func moveFocus(_ direction: Direction) {
    guard let neighbor = tree.neighbor(of: focusedID, in: direction) else { return }
    focusedID = neighbor
    focusFocusedPane()
    onChange?()
  }

  /// Closes every PTY explicitly; window teardown must not rely on `deinit` ordering.
  func terminateAll() {
    for id in tree.paneIDs { detach(id)?.terminate() }
  }

  private func closePane(_ id: PaneID) {
    guard let pane = detach(id) else { return }
    pane.terminate()
    let heir = tree.remove(id)
    if tree.isEmpty {
      onEmpty?()
      return
    }
    if id == focusedID, let heir { focusedID = heir }
    rebuildLayout()
    focusFocusedPane()
    onChange?()
  }

  private func attach(_ pane: TerminalPaneController, as id: PaneID) {
    panes[id] = pane
    addChild(pane)
    // The shell exited on its own (exit, ^D): the pane closes like ⌘W.
    pane.onClose = { [weak self] in self?.closePane(id) }
    // cwd or process changed: title, proxy icon and green dot follow the focused pane.
    pane.onStatusChange = { [weak self] in self?.onChange?() }
  }

  private func detach(_ id: PaneID) -> TerminalPaneController? {
    guard let pane = panes.removeValue(forKey: id) else { return nil }
    pane.onClose = nil
    pane.onStatusChange = nil
    pane.view.removeFromSuperview()
    pane.removeFromParent()
    return pane
  }

  private func firstResponderDidChange(_ responder: NSResponder?) {
    guard let responderView = responder as? NSView,
      let id = panes.first(where: { responderView.isDescendant(of: $0.value.view) })?.key,
      id != focusedID
    else { return }
    focusedID = id
    onChange?()
  }

  // shortcut: rebuilding resets dividers to 50/50 after a split or close; keep NSSplitView
  // instances across changes if users ask to preserve manual sizes.
  private func rebuildLayout() {
    paneArea.subviews.forEach { $0.removeFromSuperview() }
    // NSSplitView cannot split a zero-sized frame evenly; wait for the first real layout.
    needsLayoutRebuild = paneArea.bounds.isEmpty
    guard !needsLayoutRebuild, let root = tree.root else { return }
    let content = makeView(for: root, frame: paneArea.bounds)
    content.autoresizingMask = [.width, .height]
    paneArea.addSubview(content)
  }

  private func makeView(for node: SplitTree.Node, frame: NSRect) -> NSView {
    switch node {
    case .leaf(let id):
      let paneView = panes[id]?.view ?? NSView()
      paneView.frame = frame
      return paneView
    case .split(let axis, let first, let second):
      let splitView = NSSplitView(frame: frame)
      splitView.isVertical = axis == .vertical
      splitView.dividerStyle = .thin
      let (firstFrame, secondFrame) = halves(of: splitView.bounds, axis: axis)
      splitView.addArrangedSubview(makeView(for: first, frame: firstFrame))
      splitView.addArrangedSubview(makeView(for: second, frame: secondFrame))
      splitView.adjustSubviews()
      return splitView
    }
  }

  private func halves(of rect: NSRect, axis: Axis) -> (NSRect, NSRect) {
    switch axis {
    case .vertical:
      let width = rect.width / 2
      return (
        NSRect(x: 0, y: 0, width: width, height: rect.height),
        NSRect(x: width, y: 0, width: rect.width - width, height: rect.height)
      )
    case .horizontal:
      let height = rect.height / 2
      return (
        NSRect(x: 0, y: 0, width: rect.width, height: height),
        NSRect(x: 0, y: height, width: rect.width, height: rect.height - height)
      )
    }
  }

  private func applyBackground() {
    guard isViewLoaded else { return }
    view.layer?.backgroundColor = MatrixTheme.nsColor(MatrixPalette.bg, alpha: backgroundOpacity)
      .cgColor
  }
}

#Preview("Two panes") {
  let container = PaneContainerController(
    paneFactory: { [firstCommand = FirstCommandFlag.preview()] cwd, _ in
      TerminalPaneController(config: .defaults, cwd: cwd, firstCommand: firstCommand)
    }, cwd: nil)
  container.split(.vertical)
  container.split(.horizontal)
  return container
}
