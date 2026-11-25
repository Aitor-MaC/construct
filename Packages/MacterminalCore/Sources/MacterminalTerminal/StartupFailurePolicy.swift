/// Decide si el fin del shell es un arranque fallido, que deja el panel abierto con el error, o
/// una salida normal, que lo cierra (I8). Con integración, la prueba de que el arranque terminó es
/// el primer `A` autenticado; sin ella no hay señal fiable y se usa el tiempo de vida.
public enum StartupFailurePolicy {
  public static let minimumHealthyUptime = Duration.seconds(2)

  public static func keepsPaneOpen(
    integrationAvailable: Bool, sawAuthenticatedPrompt: Bool, uptime: Duration
  ) -> Bool {
    integrationAvailable ? !sawAuthenticatedPrompt : uptime < minimumHealthyUptime
  }

  public static func message(exitCode: Int32?) -> String {
    let code = exitCode.map(String.init) ?? "—"
    return String(
      localized: "The shell exited at launch (code \(code))", bundle: .localized,
      comment:
        "Error shown when the shell exits right after launching; the placeholder is the exit code or a dash."
    )
  }
}
