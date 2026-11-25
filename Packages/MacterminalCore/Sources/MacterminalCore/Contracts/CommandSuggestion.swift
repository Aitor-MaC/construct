public struct CommandSuggestion: Sendable, Equatable {
  public let command: String
  public let explanation: String?
  public init(command: String, explanation: String? = nil) {
    self.command = command
    self.explanation = explanation
  }
}
