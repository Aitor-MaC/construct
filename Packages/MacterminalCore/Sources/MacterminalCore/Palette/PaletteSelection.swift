/// Movimiento de la selección con ↑↓: se detiene en los extremos, sin dar la vuelta.
public enum PaletteSelection {
  public static func moved(_ current: Int, by delta: Int, count: Int) -> Int? {
    guard count > 0 else { return nil }
    return min(max(current + delta, 0), count - 1)
  }
}
