import Foundation
import MacterminalCore
import Testing

@testable import MacterminalTerminal

/// Puerta que el test abre cuando quiere que el "modelo" responda.
private struct Gate: Sendable {
  let stream: AsyncStream<Void>
  let continuation: AsyncStream<Void>.Continuation
  init() { (stream, continuation) = AsyncStream<Void>.makeStream() }
  func wait() async throws {
    for await _ in stream { return }
    throw CancellationError()
  }
  func open() { continuation.yield() }
}

@MainActor @Suite struct SuggestionFlowTests {
  private let token = InsertionToken(session: SessionID(), promptGeneration: 3)
  private let suggestion = CommandSuggestion(command: "ls -la", explanation: "Lista todo")

  private func flow(
    current: @escaping (InsertionToken) -> Bool = { _ in true },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    suggest: @escaping SuggestionFlow.Suggest
  ) -> SuggestionFlow {
    SuggestionFlow(suggest: suggest, isCurrent: current, sleep: sleep)
  }

  @Test func aRequestShowsLoadingAndThenTheSuggestion() async {
    let gate = Gate()
    let suggestion = suggestion
    let flow = flow { _, _ in
      try await gate.wait()
      return suggestion
    }
    flow.request("listar todo", token: token, cwd: nil)
    #expect(flow.card == .loading)
    gate.open()
    await flow.settled()
    #expect(flow.card == .result(suggestion))
  }

  @Test func insertWritesTheCommandWithTheRequestTokenAndCloses() async {
    let suggestion = suggestion
    let flow = flow { _, _ in suggestion }
    flow.request("listar todo", token: token, cwd: nil)
    await flow.settled()
    var written: [(String, InsertionToken)] = []
    let result = flow.insert(suggestion) { text, token in
      written.append((text, token))
      return .inserted
    }
    #expect(result == .inserted)
    #expect(written.map(\.0) == ["ls -la"])
    #expect(written.map(\.1) == [token])
    #expect(flow.card == nil)
  }

  @Test func aRejectedInsertKeepsTheCardAndReportsWhy() async {
    let suggestion = suggestion
    let flow = flow { _, _ in suggestion }
    flow.request("listar todo", token: token, cwd: nil)
    await flow.settled()
    let result = flow.insert(suggestion) { _, _ in .stale }
    #expect(result == .stale)
    #expect(SuggestionFlow.failureMessage(for: result) != nil)
    #expect(flow.card == .result(suggestion))
  }

  @Test func timeoutShowsTheTimeoutMessage() async {
    let flow = flow(sleep: { _ in }) { _, _ in
      try await Task.sleep(for: .seconds(3600))
      throw SuggestionError.unknown
    }
    flow.request("algo lento", token: token, cwd: nil)
    await flow.settled()
    #expect(flow.card == .failed(SuggestionFlow.timeoutMessage))
  }

  @Test func cancelClosesTheCardAndALateAnswerIsDropped() async {
    let gate = Gate()
    let suggestion = suggestion
    let flow = flow { _, _ in
      try await gate.wait()
      return suggestion
    }
    flow.request("listar todo", token: token, cwd: nil)
    flow.cancel()
    gate.open()
    await flow.settled()
    #expect(flow.card == nil)
  }

  @Test func aNewRequestReplacesThePendingOne() async {
    let gate = Gate()
    let late = CommandSuggestion(command: "rm -rf build", explanation: "Antigua")
    let fresh = suggestion
    let flow = flow { request, _ in
      if request == "primera" {
        try await gate.wait()
        return late
      }
      return fresh
    }
    let newer = InsertionToken(session: token.session, promptGeneration: 4)
    flow.request("primera", token: token, cwd: nil)
    flow.request("segunda", token: newer, cwd: nil)
    gate.open()
    await flow.settled()
    #expect(flow.card == .result(fresh))
    var used: InsertionToken?
    _ = flow.insert(fresh) { _, token in
      used = token
      return .inserted
    }
    #expect(used == newer)
  }

  @Test func anAnswerForAPromptThatMovedOnIsDiscarded() async {
    let suggestion = suggestion
    let flow = flow(current: { _ in false }) { _, _ in suggestion }
    flow.request("listar todo", token: token, cwd: nil)
    await flow.settled()
    #expect(flow.card == nil)
  }

  @Test func modelErrorsUseTheCardStates() async {
    let flow = flow { _, _ in throw SuggestionError.unavailable(reason: "Sin modelo") }
    flow.request("listar todo", token: token, cwd: nil)
    await flow.settled()
    #expect(flow.card == .unavailable(reason: "Sin modelo"))
  }

  /// Wired as in the app: a request typed while Apple Intelligence is off or still downloading
  /// opens the card with the reason instead of doing nothing, and never reaches the model.
  @Test(arguments: [ModelAvailabilityReason.appleIntelligenceNotEnabled, .modelNotReady])
  func unavailableModelExplainsWhyOnTheCard(reason: ModelAvailabilityReason) async throws {
    let backend = UnavailableBackend(reason: reason)
    let suggester = CommandSuggester(backend: backend)
    guard case .unavailable(let expected) = suggester.availability() else {
      Issue.record("the backend should be unavailable")
      return
    }
    let flow = flow { try await suggester.suggest(for: $0, cwd: $1) }
    flow.request("install powershell", token: token, cwd: nil)
    await flow.settled()
    #expect(flow.card == .unavailable(reason: expected))
  }
}

private struct UnavailableBackend: SuggestionBackend {
  let reason: ModelAvailabilityReason
  func availability() -> ModelAvailability { .unavailable(reason) }
  func generate(request: String, cwd: String?) async throws -> RawSuggestion {
    Issue.record("an unavailable model must not be asked")
    return RawSuggestion(command: "", explanation: "")
  }
}
