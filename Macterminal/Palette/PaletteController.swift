import AppKit
import MacterminalCore
import MacterminalTerminal
import SwiftUI

/// Shows the ⇧⌘P palette over a terminal window. It never runs a command: it inserts into the
/// prompt or triggers an action through the injected `perform`.
final class PaletteController {
  typealias HistoryProvider = () async -> (commands: [HistoryEntry], dirs: [URL])

  private let historyProvider: HistoryProvider
  private let canInsert: () -> Bool
  private let perform: (PaletteResult) -> InsertResult?
  private let currentIntensity: () -> Intensity?
  private let registry: ActionRegistry
  private let toasts: ToastCenter

  private var host: NSHostingView<PaletteView>?
  private var historyTask: Task<Void, Never>?
  private weak var previousResponder: NSResponder?

  var isShowing: Bool { host != nil }

  init(
    historyProvider: @escaping HistoryProvider, canInsert: @escaping () -> Bool,
    perform: @escaping (PaletteResult) -> InsertResult?,
    currentIntensity: @escaping () -> Intensity?, registry: ActionRegistry = .shared,
    toasts: ToastCenter = .shared
  ) {
    self.historyProvider = historyProvider
    self.canInsert = canInsert
    self.perform = perform
    self.currentIntensity = currentIntensity
    self.registry = registry
    self.toasts = toasts
  }

  func show(over window: NSWindow) {
    dismiss()
    guard let content = window.contentView else { return }
    let registry = registry
    let model = PaletteModel(
      actions: PaletteCatalog.actionItems(from: TerminalAction.catalog),
      currentIntensity: currentIntensity(), canInsert: canInsert,
      canPerform: { registry.canPerform($0, in: registry.context) }, perform: perform,
      toasts: toasts, onDismiss: { [weak self] in self?.dismiss() })
    let host = NSHostingView(rootView: PaletteView(model: model))
    // The overlay must not push its size onto the window; it follows the content view instead.
    host.sizingOptions = []
    host.frame = content.bounds
    host.autoresizingMask = [.width, .height]
    previousResponder = window.firstResponder
    content.addSubview(host, positioned: .above, relativeTo: nil)
    self.host = host
    historyTask = Task { [historyProvider] in
      let history = await historyProvider()
      guard !Task.isCancelled else { return }
      model.applyHistory(commands: history.commands, directories: history.dirs)
    }
  }

  func dismiss() {
    historyTask?.cancel()
    historyTask = nil
    guard let host else { return }
    let window = host.window
    host.removeFromSuperview()
    self.host = nil
    if let previousResponder, let window { window.makeFirstResponder(previousResponder) }
    previousResponder = nil
  }

  /// ⇧⌘P toggles the palette over the window that has the focus. T14 calls this once at launch.
  static func registerActions(in registry: ActionRegistry, palette: PaletteController) {
    registry.register(.commandPalette, isEnabled: { $0.window != nil }) { context in
      guard let window = context.window else { return }
      if palette.isShowing, palette.host?.window === window {
        palette.dismiss()
      } else {
        palette.show(over: window)
      }
    }
  }
}
