public enum Intensity: String, Sendable, CaseIterable {
  case sutil, equilibrado, inmersivo

  /// Valor del archivo de configuración. El `rawValue` en español es el que se escribe (no rompe
  /// configs existentes); los nombres ingleses se aceptan también al leer.
  public init?(configValue: String) {
    switch configValue {
    case "subtle": self = .sutil
    case "balanced": self = .equilibrado
    case "immersive": self = .inmersivo
    default: self.init(rawValue: configValue)
    }
  }

  public var profile: IntensityProfile {
    switch self {
    case .sutil:
      .init(
        accentGlowRadius: 0, accentGlowAlpha: 0, textGlowRadius: 0, textGlowAlpha: 0,
        activeColumnFraction: 0.18, speed: 8...14, trailLength: 8...14, headAlpha: 0.14,
        trailAlpha: 0.07, mutationRate: 0.6, typingAlphaMultiplier: 0, scanlines: false,
        vignetteAlpha: 0, wakeUp: false)
    case .equilibrado:
      .init(
        accentGlowRadius: 6, accentGlowAlpha: 0.35, textGlowRadius: 0, textGlowAlpha: 0,
        activeColumnFraction: 0.35, speed: 10...18, trailLength: 10...20, headAlpha: 0.25,
        trailAlpha: 0.12, mutationRate: 1.2, typingAlphaMultiplier: 0.5, scanlines: false,
        vignetteAlpha: 0, wakeUp: false)
    case .inmersivo:
      .init(
        accentGlowRadius: 8, accentGlowAlpha: 0.55, textGlowRadius: 2, textGlowAlpha: 0.25,
        activeColumnFraction: 0.60, speed: 12...24, trailLength: 14...28, headAlpha: 0.45,
        trailAlpha: 0.22, mutationRate: 2, typingAlphaMultiplier: 0.5, scanlines: true,
        vignetteAlpha: 0.45, wakeUp: true)
    }
  }
}
