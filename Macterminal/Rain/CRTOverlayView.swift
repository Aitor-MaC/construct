import AppKit
import MacterminalCore

/// Scanlines y viñeta encima del texto, solo en Inmersivo. Son capas estáticas: se rehacen al
/// cambiar el tamaño, nunca por fotograma. Sin curvatura, jitter, flicker ni aberración.
final class CRTOverlayView: NSView {
  var intensity: Intensity {
    didSet { if intensity != oldValue { applyIntensity(animated: !reduceMotion) } }
  }
  var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  /// Aumentar contraste quita las scanlines y la viñeta.
  var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
    didSet { if increaseContrast != oldValue { applyIntensity(animated: !reduceMotion) } }
  }

  private let scanlines = CAShapeLayer()
  private let vignette = CAGradientLayer()

  init(intensity: Intensity) {
    self.intensity = intensity
    super.init(frame: .zero)
    wantsLayer = true
    setAccessibilityElement(false)
    configureLayers()
    applyIntensity(animated: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isOpaque: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scanlines.frame = bounds
    scanlines.path = Self.scanlinePath(in: bounds)
    vignette.frame = bounds
    CATransaction.commit()
  }

  private func configureLayers() {
    let profile = Intensity.inmersivo.profile
    // Multiplicar por negro al α equivale a pintar negro al α encima, así que no hace falta un
    // filtro de composición (obligaría a Core Image en toda la jerarquía). El negro es `void`,
    // el más oscuro de la paleta: la diferencia con #000 al 16 % no llega a 1/255.
    scanlines.fillColor = MatrixTheme.nsColor(MatrixPalette.void, alpha: profile.scanlineAlpha)
      .cgColor
    // Radial 120 % × 90 % centrada al 45 % de alto, transparente hasta el 60 % (mock F1).
    vignette.type = .radial
    vignette.startPoint = CGPoint(x: 0.5, y: 0.55)
    vignette.endPoint = CGPoint(x: 0.5 + 1.2, y: 0.55 + 0.9)
    vignette.colors = [
      MatrixTheme.nsColor(MatrixPalette.void, alpha: 0).cgColor,
      MatrixTheme.nsColor(MatrixPalette.void, alpha: 0).cgColor,
      MatrixTheme.nsColor(MatrixPalette.void, alpha: profile.vignetteAlpha).cgColor,
    ]
    vignette.locations = [0, 0.6, 1]
    layer?.addSublayer(vignette)
    layer?.addSublayer(scanlines)
  }

  private func applyIntensity(animated: Bool) {
    let profile = intensity.profile
    let allowed = !increaseContrast
    IntensityCrossfade.perform(animated: animated) {
      scanlines.opacity = allowed && profile.scanlines ? 1 : 0
      vignette.opacity = allowed && profile.vignetteAlpha > 0 ? 1 : 0
    }
  }

  /// Periodo de 3 pt: dos filas limpias y una oscura, contadas desde arriba.
  private static func scanlinePath(in bounds: CGRect) -> CGPath {
    let path = CGMutablePath()
    let period = CGFloat(Intensity.inmersivo.profile.scanlinePeriodPixels)
    guard bounds.height.isFinite, bounds.height > 0, period > 0 else { return path }
    var offset = period - 1
    while offset < bounds.height {
      path.addRect(CGRect(x: 0, y: bounds.height - offset - 1, width: bounds.width, height: 1))
      offset += period
    }
    return path
  }
}
