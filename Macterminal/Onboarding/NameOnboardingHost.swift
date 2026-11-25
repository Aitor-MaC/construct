import AppKit
import SwiftUI

/// Aloja `NameOnboardingView` sobre la terminal y no suelta el foco mientras está en la ventana:
/// la terminal (o el contenedor de paneles al hacer su primer layout) puede reclamarlo, y
/// entonces las teclas del nombre acabarían en el PTY. Cualquier cambio de first responder
/// fuera del overlay se devuelve a su campo de texto.
final class NameOnboardingHost: NSHostingView<NameOnboardingView> {
  private var focusObservation: NSKeyValueObservation?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    focusObservation = nil
    guard let window else { return }
    focusObservation = window.observe(\.firstResponder, options: [.initial, .new]) {
      [weak self] window, _ in
      // AppKit cambia el first responder solo en el hilo principal.
      MainActor.assumeIsolated { self?.reclaimFocus(from: window.firstResponder) }
    }
  }

  private func reclaimFocus(from responder: NSResponder?) {
    if let view = responder as? NSView, view.isDescendant(of: self) { return }
    // Fuera del cambio en curso: dentro del aviso KVO, AppKit aún no ha terminado de asignarlo.
    Task { [weak self] in
      guard let self, let window, let field = Self.textField(in: self) else { return }
      if let view = window.firstResponder as? NSView, view.isDescendant(of: self) { return }
      window.makeFirstResponder(field)
    }
  }

  /// El `TextField` de SwiftUI en macOS es un `NSTextField` editable dentro de la jerarquía.
  private static func textField(in view: NSView) -> NSTextField? {
    for subview in view.subviews {
      if let field = subview as? NSTextField, field.isEditable { return field }
      if let found = textField(in: subview) { return found }
    }
    return nil
  }
}
