import QuartzCore

/// Transición común del cambio de intensidad para glow y overlays (dirección 4.6).
enum IntensityCrossfade {
  static let duration: CFTimeInterval = 0.22

  /// Aplica `changes` a capas sueltas con crossfade ease-out, o al instante con Reduce Motion.
  static func perform(animated: Bool, _ changes: () -> Void) {
    CATransaction.begin()
    if animated {
      CATransaction.setAnimationDuration(duration)
      CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
    } else {
      CATransaction.setDisableActions(true)
    }
    changes()
    CATransaction.commit()
  }
}
