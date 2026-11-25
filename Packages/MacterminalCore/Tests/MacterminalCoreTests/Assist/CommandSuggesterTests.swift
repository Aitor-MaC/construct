import Foundation
import FoundationModels
import Testing

@testable import MacterminalCore

/// Backend simulado: no se invoca el modelo real en tests.
private final class FakeBackend: SuggestionBackend, @unchecked Sendable {
  private let lock = NSLock()
  private var _calls: [(request: String, cwd: String?)] = []
  var modelAvailability: ModelAvailability = .available
  var result: Result<RawSuggestion, any Error> = .success(
    RawSuggestion(command: "ls", explanation: "lista"))
  var delay: Duration?

  var calls: [(request: String, cwd: String?)] { lock.withLock { _calls } }

  func availability() -> ModelAvailability { modelAvailability }

  func generate(request: String, cwd: String?) async throws -> RawSuggestion {
    lock.withLock { _calls.append((request, cwd)) }
    if let delay { try await Task.sleep(for: delay) }
    return try result.get()
  }
}

@Suite("CommandSuggester.sanitize")
struct SanitizeTests {
  private func clean(_ command: String, _ explanation: String? = nil) -> CommandSuggestion? {
    CommandSuggester.sanitize(CommandSuggestion(command: command, explanation: explanation))
  }

  @Test func plainCommandPassesThroughTrimmed() {
    #expect(clean("  ls -la  ")?.command == "ls -la")
  }

  @Test func newlinesBecomeSpacesAndCommandStaysOnOneLine() throws {
    let result = try #require(clean("echo a\necho b\r\nrm x\u{2028}y\u{85}z"))
    #expect(!result.command.unicodeScalars.contains { $0.value == 0x0A || $0.value == 0x0D })
    #expect(result.command == "echo a echo b rm x y z")
  }

  @Test func escapeSequencesAreStripped() throws {
    let result = try #require(clean("\u{1B}]7777;00000000000000000000000000000000;C;aGk=\u{07}ls"))
    #expect(!result.command.unicodeScalars.contains { $0.value == 0x1B || $0.value == 0x07 })
    #expect(result.command.hasSuffix("ls"))
  }

  @Test(
    "elimina controles, C1, bidi y ancho cero",
    arguments: [
      0x00, 0x01, 0x07, 0x08, 0x1B, 0x1F, 0x7F,
      0x80, 0x9B, 0x9F,
      0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0xFEFF,
      0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
      0x2066, 0x2067, 0x2068, 0x2069,
    ])
  func hostileScalarsAreRemoved(value: Int) throws {
    let scalar = try #require(UnicodeScalar(value))
    let result = try #require(clean("a\(Character(scalar))b"))
    #expect(result.command == "ab")
  }

  @Test func tabBecomesSpaceSoItCannotTriggerCompletion() throws {
    #expect(try #require(clean("a\tb")).command == "a b")
    #expect(try #require(clean("a\u{0B}b\u{0C}c")).command == "a b c")
  }

  @Test func longCommandIsCutAt500Characters() throws {
    let result = try #require(clean(String(repeating: "a", count: 10_000)))
    #expect(result.command.count == 500)
  }

  @Test func combiningMarkFloodStaysBounded() throws {
    let flood = "a" + String(repeating: "\u{0301}", count: 100_000)
    let result = try #require(clean(flood))
    #expect(result.command.unicodeScalars.count <= 4000)
  }

  @Test(
    "nil si queda vacío", arguments: ["", "   ", "\n\n", "\u{1B}", "\u{200B}\u{202E}", "\t \r"])
  func emptyAfterCleaningIsNil(command: String) {
    #expect(clean(command) == nil)
  }

  @Test func explanationIsCleanedAndEmptyBecomesNil() {
    #expect(clean("ls", "lista\narchivos\u{1B}")?.explanation == "lista archivos")
    #expect(clean("ls", "  \n ")?.explanation == nil)
    #expect(clean("ls", nil)?.explanation == nil)
    #expect(clean("ls", String(repeating: "x", count: 5000))?.explanation?.count == 500)
  }

  @Test func unicodeCommandsAreKept() {
    #expect(clean("echo \"héllo 日本 🙂\"")?.command == "echo \"héllo 日本 🙂\"")
  }
}

@Suite("CommandSuggester")
struct CommandSuggesterTests {
  @Test func availabilityMapsEveryReasonToText() {
    let reasons: [ModelAvailabilityReason] = [
      .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .other,
    ]
    var texts = Set<String>()
    for reason in reasons {
      let backend = FakeBackend()
      backend.modelAvailability = .unavailable(reason)
      guard case .unavailable(let text) = CommandSuggester(backend: backend).availability() else {
        Issue.record("debería no estar disponible: \(reason)")
        continue
      }
      #expect(!text.isEmpty)
      texts.insert(text)
    }
    #expect(texts.count == reasons.count)
  }

  @Test func availableBackendIsAvailable() {
    #expect(CommandSuggester(backend: FakeBackend()).availability() == .available)
    #expect(CommandSuggester(backend: FakeBackend()).availabilityWithReason().reason == nil)
  }

  @Test(arguments: [
    (ModelAvailabilityReason.modelNotReady, true),
    (.appleIntelligenceNotEnabled, true),
    (.deviceNotEligible, false),
    (.other, false),
  ])
  func availabilityExposesRawReasonAndWhetherItIsTransient(reason: ModelAvailabilityReason, transient: Bool) {
    let backend = FakeBackend()
    backend.modelAvailability = .unavailable(reason)
    let result = CommandSuggester(backend: backend).availabilityWithReason()
    #expect(result.reason == reason)
    #expect(result.availability == CommandSuggester(backend: backend).availability())
    #expect(reason.isTransient == transient)
  }

  @Test func realBackendAvailabilityNeverCrashes() {
    let result = CommandSuggester().availability()
    switch result {
    case .available: break
    case .unavailable(let reason): #expect(!reason.isEmpty)
    }
  }

  @Test(
    "every model failure has a message",
    arguments: [
      ModelFailure.guardrailViolation, .exceededContextWindowSize, .rateLimited,
      .concurrentRequests,
      .unsupportedLanguageOrLocale, .modelAssetsUnavailable, .unknown,
    ])
  func everyFailureHasAMessage(failure: ModelFailure) {
    let error = SuggestionError(failure: failure)
    #expect((error.errorDescription ?? "").isEmpty == false)
  }

  @Test func allErrorsHaveDistinctMessages() {
    let errors: [SuggestionError] = [
      .unavailable(reason: "x"), .cancelled, .invalidOutput, .emptyRequest, .guardrailViolation,
      .exceededContextWindowSize, .rateLimited, .concurrentRequests, .unsupportedLanguageOrLocale,
      .modelAssetsUnavailable, .unknown,
    ]
    let messages = errors.compactMap(\.errorDescription)
    #expect(messages.count == errors.count)
    #expect(Set(messages).count == errors.count)
  }

  @Test func suggestReturnsSanitizedResult() async throws {
    let backend = FakeBackend()
    backend.result = .success(
      RawSuggestion(command: "\u{1B}[2Jls\n-la\u{202E}", explanation: "lista\u{1B}"))
    let suggestion = try await CommandSuggester(backend: backend).suggest(
      for: "lista archivos", cwd: URL(filePath: "/work"))
    #expect(suggestion.command == "[2Jls -la")
    #expect(suggestion.explanation == "lista")
  }

  @Test func suggestionNeverContainsReturn() async throws {
    let backend = FakeBackend()
    backend.result = .success(RawSuggestion(command: "rm -rf /tmp/x\r", explanation: "a\rb"))
    let suggestion = try await CommandSuggester(backend: backend).suggest(for: "x", cwd: nil)
    #expect(!suggestion.command.contains("\r"))
    #expect(!(suggestion.explanation ?? "").contains("\r"))
  }

  @Test func onlyRequestAndCwdReachTheBackend() async throws {
    let backend = FakeBackend()
    _ = try await CommandSuggester(backend: backend).suggest(
      for: "comprime esta carpeta", cwd: URL(filePath: "/Users/x/proyecto"))
    #expect(backend.calls.count == 1)
    #expect(backend.calls[0].request == "comprime esta carpeta")
    #expect(backend.calls[0].cwd == "/Users/x/proyecto")
  }

  @Test func nilCwdIsPassedAsNil() async throws {
    let backend = FakeBackend()
    _ = try await CommandSuggester(backend: backend).suggest(for: "x", cwd: nil)
    #expect(backend.calls[0].cwd == nil)
  }

  @Test func overlongRequestIsTruncatedBeforeSending() async throws {
    let backend = FakeBackend()
    _ = try await CommandSuggester(backend: backend).suggest(
      for: String(repeating: "a", count: 100_000), cwd: nil)
    #expect(backend.calls[0].request.count <= CommandSuggester.maxRequestCharacters)
  }

  @Test func blankRequestIsRejectedWithoutCallingTheModel() async {
    let backend = FakeBackend()
    await #expect(throws: SuggestionError.emptyRequest) {
      _ = try await CommandSuggester(backend: backend).suggest(for: "  \n", cwd: nil)
    }
    #expect(backend.calls.isEmpty)
  }

  @Test func unavailableModelThrowsAndDoesNotCallBackend() async {
    let backend = FakeBackend()
    backend.modelAvailability = .unavailable(.appleIntelligenceNotEnabled)
    do {
      _ = try await CommandSuggester(backend: backend).suggest(for: "x", cwd: nil)
      Issue.record("debía lanzar")
    } catch let error as SuggestionError {
      guard case .unavailable(let reason) = error else {
        Issue.record("error inesperado \(error)")
        return
      }
      #expect(!reason.isEmpty)
    } catch {
      Issue.record("error inesperado \(error)")
    }
    #expect(backend.calls.isEmpty)
  }

  @Test func outputThatSanitizesToNothingIsInvalid() async {
    let backend = FakeBackend()
    backend.result = .success(RawSuggestion(command: "\u{1B}\n\u{200B}", explanation: "x"))
    await #expect(throws: SuggestionError.invalidOutput) {
      _ = try await CommandSuggester(backend: backend).suggest(for: "x", cwd: nil)
    }
  }

  @Test(
    "los fallos del backend se mapean",
    arguments: [
      (ModelFailure.guardrailViolation, SuggestionError.guardrailViolation),
      (.exceededContextWindowSize, .exceededContextWindowSize),
      (.rateLimited, .rateLimited),
      (.concurrentRequests, .concurrentRequests),
      (.unsupportedLanguageOrLocale, .unsupportedLanguageOrLocale),
      (.modelAssetsUnavailable, .modelAssetsUnavailable),
      (.unknown, .unknown),
    ])
  func backendFailuresAreMapped(failure: ModelFailure, expected: SuggestionError) async {
    let backend = FakeBackend()
    backend.result = .failure(ModelFailureError(failure))
    await #expect(throws: expected) {
      _ = try await CommandSuggester(backend: backend).suggest(for: "x", cwd: nil)
    }
  }

  @Test func foreignErrorsBecomeUnknown() async {
    struct Other: Error {}
    let backend = FakeBackend()
    backend.result = .failure(Other())
    await #expect(throws: SuggestionError.unknown) {
      _ = try await CommandSuggester(backend: backend).suggest(for: "x", cwd: nil)
    }
  }

  @Test func cancelledTaskThrowsCancelledAndPublishesNothing() async {
    let backend = FakeBackend()
    backend.delay = .seconds(30)
    let suggester = CommandSuggester(backend: backend)
    let task = Task { try await suggester.suggest(for: "x", cwd: nil) }
    // Espera a que el backend haya recibido la petición (señal observable, sin dormir a ciegas).
    while backend.calls.isEmpty { await Task.yield() }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("debía cancelarse")
    } catch {
      #expect(error as? SuggestionError == .cancelled)
    }
  }

  @Test func alreadyCancelledTaskDoesNotCallBackend() async {
    let backend = FakeBackend()
    let suggester = CommandSuggester(backend: backend)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try await suggester.suggest(for: "x", cwd: nil)
    }
    do {
      _ = try await task.value
      Issue.record("debía cancelarse")
    } catch {
      #expect(error as? SuggestionError == .cancelled)
    }
    #expect(backend.calls.isEmpty)
  }
}

@Suite("SystemModelBackend.classify")
struct ClassifyModelErrorTests {
  private static let cases: [(String, any Error, ModelFailure)] = [
    (
      "guardrail", LanguageModelError.guardrailViolation(.init(debugDescription: "x")),
      .guardrailViolation
    ),
    (
      "refusal", LanguageModelError.refusal(.init(explanation: "no", debugDescription: "x")),
      .guardrailViolation
    ),
    (
      "contexto",
      LanguageModelError.contextSizeExceeded(
        .init(contextSize: 10, tokenCount: 20, debugDescription: "x")),
      .exceededContextWindowSize
    ),
    (
      "límite", LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "x")),
      .rateLimited
    ),
    (
      "idioma",
      LanguageModelError.unsupportedLanguageOrLocale(
        .init(languageCode: Locale.LanguageCode("xx"), debugDescription: "x")),
      .unsupportedLanguageOrLocale
    ),
    ("timeout", LanguageModelError.timeout(.init(debugDescription: "x")), .unknown),
    ("simultáneas", LanguageModelSession.Error.concurrentRequests, .concurrentRequests),
    (
      "activos",
      SystemLanguageModel.Error.assetsUnavailable(.init(debugDescription: "x")),
      .modelAssetsUnavailable
    ),
    ("ajeno", CocoaError(.fileNoSuchFile), .unknown),
  ]

  @Test func mapsEachRealSDKError() {
    for (name, error, expected) in Self.cases {
      #expect(SystemModelBackend.classify(error) == expected, "caso \(name)")
    }
  }
}
