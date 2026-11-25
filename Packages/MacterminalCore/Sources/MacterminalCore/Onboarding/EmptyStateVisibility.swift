/// Cuándo se ve el estado vacío de un panel ("New session…"): es ayuda de primer uso, así que
/// deja de salir en todos los paneles en cuanto el usuario ejecuta su primer comando o lo cierra.
public enum EmptyStateVisibility {
  /// `promptGeneration == 0`: aún no llegó un prompt autenticado y no hay dónde colocarlo. Con el
  /// aviso de integración visible manda el aviso.
  public static func shouldShow(
    hasRunFirstCommand: Bool, promptGeneration: UInt64, bannerVisible: Bool
  ) -> Bool {
    !hasRunFirstCommand && promptGeneration > 0 && !bannerVisible
  }
}
