/// Si una fila se puede elegir ahora y, si no, por qué (texto visible, no solo el color atenuado).
public enum PaletteAvailability: Sendable, Equatable {
  case enabled
  case disabled(reason: String)

  public static var promptRequiredReason: String {
    String(
      localized: "Available when the prompt is active", bundle: .localized,
      comment: "Command palette: why a row can't be chosen right now.")
  }
  public static var actionUnavailableReason: String {
    String(
      localized: "Not available now", bundle: .localized,
      comment: "Command palette: why a row can't be chosen right now.")
  }

  public static func of(
    _ item: PaletteItem, canInsert: Bool, canPerform: (TerminalAction) -> Bool
  ) -> PaletteAvailability {
    switch item.run {
    case .insert: canInsert ? .enabled : .disabled(reason: promptRequiredReason)
    case .action(let action):
      canPerform(action) ? .enabled : .disabled(reason: actionUnavailableReason)
    }
  }
}
