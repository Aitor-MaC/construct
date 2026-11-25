import AppKit
import MacterminalCore
import SwiftUI

/// Capa superior de cada ventana de terminal con los toasts de `ToastCenter.shared`. Una por
/// ventana y no por panel: con splits, el aviso sale una vez, abajo a la derecha de la ventana.
/// No recibe clics ni foco.
final class WindowToastLayer: NSHostingView<ToastView> {
  private static let identifier = NSUserInterfaceItemIdentifier("com.aitorgarcia.Macterminal.toasts")

  /// Idempotente: la primera vez que un panel aparece en una ventana.
  static func install(in window: NSWindow) {
    guard let content = window.contentView,
      !content.subviews.contains(where: { $0.identifier == identifier })
    else { return }
    let layer = WindowToastLayer(rootView: ToastView(center: .shared))
    layer.identifier = identifier
    layer.sizingOptions = []
    layer.frame = content.bounds
    layer.autoresizingMask = [.width, .height]
    content.addSubview(layer, positioned: .above, relativeTo: nil)
  }

  override var acceptsFirstResponder: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
