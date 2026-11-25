public enum SuggestionAvailability: Sendable, Equatable {
  case available
  case unavailable(reason: String)
}
