import Testing

@testable import MacterminalCore

@Suite(.language("en")) struct SuggestionCardStateTests {
  @Test func onlyAResultCanBeInserted() {
    let suggestion = CommandSuggestion(command: "ls -la", explanation: "Lista todo.")
    #expect(SuggestionCardState.result(suggestion).insertable == suggestion)
    #expect(SuggestionCardState.loading.insertable == nil)
    #expect(SuggestionCardState.unavailable(reason: "x").insertable == nil)
    #expect(SuggestionCardState.failed("x").insertable == nil)
  }

  @Test func unavailableErrorKeepsTheReason() {
    let reason = "Apple Intelligence está desactivado. Actívalo en Ajustes del Sistema."
    #expect(
      SuggestionCardState(error: .unavailable(reason: reason)) == .unavailable(reason: reason))
  }

  @Test func cancellationClosesTheCardInsteadOfShowingAnError() {
    #expect(SuggestionCardState(error: .cancelled) == nil)
  }

  @Test(arguments: [
    SuggestionError.invalidOutput, .guardrailViolation, .rateLimited, .concurrentRequests,
    .emptyRequest, .exceededContextWindowSize, .unsupportedLanguageOrLocale,
    .modelAssetsUnavailable, .unknown,
  ])
  func otherErrorsShowTheirMessage(error: SuggestionError) throws {
    let message = try #require(error.errorDescription)
    #expect(SuggestionCardState(error: error) == .failed(message))
  }

  @Test func accessibilityReadsCommandAndExplanation() {
    let withExplanation = SuggestionCardState.result(
      CommandSuggestion(command: "du -sh *", explanation: "Size of each item."))
    #expect(
      withExplanation.accessibilityDescription
        == "Suggestion: du -sh *. Size of each item.")
    let bare = SuggestionCardState.result(CommandSuggestion(command: "pwd"))
    #expect(bare.accessibilityDescription == "Suggestion: pwd.")
    #expect(SuggestionCardState.loading.accessibilityDescription == "Generating suggestion.")
    #expect(SuggestionCardState.failed("Failed.").accessibilityDescription == "Failed.")
  }
}
