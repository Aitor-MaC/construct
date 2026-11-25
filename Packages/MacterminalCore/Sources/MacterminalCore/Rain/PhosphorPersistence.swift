/// Persistencia de fósforo del cursor: al moverse deja una copia que se apaga (tubo P1).
public enum PhosphorPersistence {
  public static let startAlpha = 0.55
  /// Apagado lineal de `startAlpha` a 0.
  public static let fade: Duration = .milliseconds(140)

  /// Celda donde dejar la copia, o `nil` si no hay movimiento o el efecto está desactivado
  /// (Sutil, Reduce Motion y Aumentar contraste, que fuerza Sutil).
  public static func ghostCell(
    from previous: GridPosition?, to current: GridPosition?, intensity: Intensity,
    reduceMotion: Bool, increaseContrast: Bool
  ) -> GridPosition? {
    guard intensity != .sutil, !reduceMotion, !increaseContrast else { return nil }
    guard let previous, previous != current else { return nil }
    return previous
  }
}
