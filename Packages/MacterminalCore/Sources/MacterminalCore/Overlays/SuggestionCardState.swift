import Foundation

/// Lo que muestra la tarjeta de sugerencia de la IA de un panel.
public enum SuggestionCardState: Sendable, Equatable {
  case loading
  case result(CommandSuggestion)
  case unavailable(reason: String)
  case failed(String)

  /// Estado para un fallo de `CommandSuggester`. `nil` para `.cancelled`: la cancelación la pidió
  /// el usuario (o el panel se cerró), así que la tarjeta se cierra en vez de mostrar un error.
  public init?(error: SuggestionError) {
    switch error {
    case .cancelled:
      return nil
    case .unavailable(let reason):
      self = .unavailable(reason: reason)
    default:
      self = .failed(
        error.errorDescription
          ?? String(
            localized: "The suggestion couldn’t be generated.", bundle: .localized,
            comment: "AI suggestion card error."))
    }
  }

  /// La sugerencia que "Insertar" entregaría; solo existe con un resultado.
  public var insertable: CommandSuggestion? {
    if case .result(let suggestion) = self { suggestion } else { nil }
  }

  /// Lo que VoiceOver lee de la tarjeta: comando y explicación, o el motivo del estado.
  public var accessibilityDescription: String {
    switch self {
    case .loading:
      return String(
        localized: "Generating suggestion.", bundle: .localized,
        comment: "VoiceOver description of the AI suggestion card while it loads.")
    case .result(let suggestion):
      let command = String(
        localized: "Suggestion: \(suggestion.command).", bundle: .localized,
        comment: "VoiceOver description of the AI suggestion card; the placeholder is the command.")
      guard let explanation = suggestion.explanation, !explanation.isEmpty else { return command }
      return "\(command) \(explanation)"
    case .unavailable(let reason):
      return reason
    case .failed(let message):
      return message
    }
  }
}
