/// Cuándo se pregunta el nombre en el primer arranque.
public enum OnboardingPolicy {
  /// Solo sin nombre en el config y sin haber contestado antes: "Ahora no" también cuenta como
  /// contestado, para no insistir en cada arranque.
  public static func shouldAsk(hasConfiguredName: Bool, completedFlag: Bool) -> Bool {
    !hasConfiguredName && !completedFlag
  }
}
