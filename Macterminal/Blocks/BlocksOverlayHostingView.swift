import AppKit
import SwiftUI

/// Aloja `BlocksOverlayView` encima de la terminal sin robarle eventos: el clic solo se queda
/// aquí sobre un control (acciones, botón del estado vacío, aviso) o, si es secundario, sobre un
/// bloque (menú contextual). Todo lo demás —selección de texto, rueda, teclado— sigue en la
/// terminal. El hover se lee con un área de rastreo propia, que no depende de `hitTest`.
final class BlocksOverlayHostingView: NSHostingView<BlocksOverlayView> {
  private var hoverArea: NSTrackingArea?

  override var acceptsFirstResponder: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    let secondary = NSApp.currentEvent.map { $0.type == .rightMouseDown } ?? false
    guard rootView.state.acceptsClick(at: swiftUIPoint(convert(point, from: superview)), secondary: secondary)
    else { return nil }
    return super.hitTest(point)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let hoverArea { removeTrackingArea(hoverArea) }
    let area = NSTrackingArea(
      rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    hoverArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    updateHover(event)
  }

  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    updateHover(event)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    rootView.state.hoveredRow = nil
  }

  private func updateHover(_ event: NSEvent) {
    let point = swiftUIPoint(convert(event.locationInWindow, from: nil))
    let row = BlockGeometry(viewport: rootView.viewport).row(at: point.y)
    if rootView.state.hoveredRow != row { rootView.state.hoveredRow = row }
  }

  /// SwiftUI mide desde arriba; la vista puede no estar volteada.
  private func swiftUIPoint(_ local: NSPoint) -> CGPoint {
    isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
  }
}
