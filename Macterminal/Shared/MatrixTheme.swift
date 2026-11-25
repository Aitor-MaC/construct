import AppKit
import MacterminalCore
import SwiftUI

public enum MatrixTheme {
  public static func nsColor(_ rgb: RGB, alpha: Double = 1) -> NSColor {
    NSColor(
      srgbRed: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255,
      alpha: alpha)
  }
  public static func color(_ rgb: RGB, alpha: Double = 1) -> Color {
    Color(nsColor: nsColor(rgb, alpha: alpha))
  }
}
