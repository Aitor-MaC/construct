import AppKit
import MacterminalCore
import SwiftUI

/// HUD material over the terminal; opaque `surface2` when the user asks for less transparency.
struct PaletteBackground: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.paletteForcesOpaque) private var forcesOpaque

  var body: some View {
    if reduceTransparency || forcesOpaque {
      MatrixTheme.color(MatrixPalette.surface2)
    } else {
      // The dark HUD material is neutral grey; the phosphor tint (mock: surface1 at 86 %) keeps it Matrix.
      HUDMaterial().overlay(MatrixTheme.color(MatrixPalette.surface1, alpha: 0.86))
    }
  }
}

extension EnvironmentValues {
  /// The system setting is read-only, so previews show the opaque variant through this value.
  @Entry var paletteForcesOpaque = false
}

private struct HUDMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    // The palette floats over the terminal inside the same window, so it blurs that content.
    view.blendingMode = .withinWindow
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
