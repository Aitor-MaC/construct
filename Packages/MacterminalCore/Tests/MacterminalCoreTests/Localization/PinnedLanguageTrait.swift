import MacterminalCore
import Testing

/// Runs the test with every package message resolved in `language`, whatever the run's language.
struct PinnedLanguage: TestTrait, SuiteTrait, TestScoping {
  let language: String
  var isRecursive: Bool { true }

  func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    try await Localization.$language.withValue(language) { try await function() }
  }
}

extension Trait where Self == PinnedLanguage {
  static func language(_ code: String) -> Self { PinnedLanguage(language: code) }
}
