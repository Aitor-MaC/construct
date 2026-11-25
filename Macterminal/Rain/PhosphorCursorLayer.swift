import AppKit
import MacterminalCore

/// Glow del cursor y su persistencia de fósforo. `layer` va en la capa de la lluvia, por debajo
/// del texto: el cursor real lo pinta la terminal y tapa la celda. Origen abajo-izquierda, como
/// el layer de `RainCanvasView`; `cursor` en filas de la vista (0 = arriba). No hereda de
/// `CALayer` para seguir aislada en MainActor como el resto de la capa AppKit.
final class PhosphorCursorLayer {
  let layer = CALayer()
  var frame: CGRect = .zero {
    didSet {
      guard frame != oldValue else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.frame = frame
      CATransaction.commit()
      placeHalo()
    }
  }
  var cursor: GridPosition? {
    didSet {
      guard cursor != oldValue else { return }
      leaveGhost(from: oldValue)
      placeHalo()
    }
  }
  var cellSize: CGSize = .zero {
    didSet { if cellSize != oldValue { placeHalo() } }
  }
  var intensity: Intensity = .equilibrado {
    didSet { if intensity != oldValue { applyGlow(animated: !reduceMotion) } }
  }
  var reduceMotion = false
  var increaseContrast = false {
    didSet { if increaseContrast != oldValue { applyGlow(animated: !reduceMotion) } }
  }

  /// Con tecleo rápido se solapan como mucho dos o tres copias (140 ms cada una).
  private let ghosts = (0..<3).map { _ in CALayer() }
  private var nextGhost = 0
  private let halo = CALayer()
  private let haloMask = CAShapeLayer()

  init() {
    let phosphor = MatrixTheme.nsColor(MatrixPalette.cursor).cgColor
    for ghost in ghosts {
      ghost.backgroundColor = phosphor
      ghost.opacity = 0
      layer.addSublayer(ghost)
    }
    halo.shadowColor = phosphor
    halo.shadowOffset = .zero
    halo.isHidden = true
    // El glow solo rodea la celda: con el parpadeo del cursor no queda un bloque verde detrás.
    haloMask.fillRule = .evenOdd
    halo.mask = haloMask
    layer.addSublayer(halo)
    applyGlow(animated: false)
  }

  private func cellRect(_ position: GridPosition) -> CGRect? {
    let width = cellSize.width
    let height = cellSize.height
    guard width.isFinite, height.isFinite, width > 0, height > 0, position.col >= 0,
      position.row >= 0
    else { return nil }
    return CGRect(
      x: CGFloat(position.col) * width, y: frame.height - CGFloat(position.row + 1) * height,
      width: width, height: height)
  }

  private func placeHalo() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    guard let cursor, let rect = cellRect(cursor) else {
      halo.isHidden = true
      return
    }
    let reach = max(Intensity.inmersivo.profile.accentGlowRadius * 3, 1)
    halo.frame = rect.insetBy(dx: -reach, dy: -reach)
    let inner = CGRect(x: reach, y: reach, width: rect.width, height: rect.height)
    halo.shadowPath = CGPath(rect: inner, transform: nil)
    let ring = CGMutablePath()
    ring.addRect(halo.bounds)
    ring.addRect(inner)
    haloMask.frame = halo.bounds
    haloMask.path = ring
    halo.isHidden = false
  }

  private func applyGlow(animated: Bool) {
    let profile = intensity.profile
    let enabled = !increaseContrast
    IntensityCrossfade.perform(animated: animated) {
      halo.shadowRadius = profile.accentGlowRadius
      halo.shadowOpacity = enabled ? Float(profile.accentGlowAlpha) : 0
    }
  }

  private func leaveGhost(from previous: GridPosition?) {
    guard
      let cell = PhosphorPersistence.ghostCell(
        from: previous, to: cursor, intensity: intensity, reduceMotion: reduceMotion,
        increaseContrast: increaseContrast),
      let rect = cellRect(cell)
    else { return }
    let ghost = ghosts[nextGhost]
    nextGhost = (nextGhost + 1) % ghosts.count
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ghost.frame = rect
    ghost.opacity = 0
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = PhosphorPersistence.startAlpha
    fade.toValue = 0
    fade.duration = PhosphorPersistence.fade / .seconds(1)
    fade.timingFunction = CAMediaTimingFunction(name: .linear)
    ghost.add(fade, forKey: "phosphor")
    CATransaction.commit()
  }
}
