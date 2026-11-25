import Foundation
import MacterminalCore
import Observation

/// Petición `# …` de un panel a la IA (A8, I11). La sugerencia queda ligada al `InsertionToken`
/// del prompt que la pidió; la tarea se guarda y se cancela con esc, al cerrar el panel o con una
/// petición nueva. Tras 20 s sin respuesta se da por perdida, y una respuesta que llega cuando el
/// prompt ya cambió se descarta. Nunca escribe en el PTY por sí misma: `insert` lo delega.
@MainActor @Observable public final class SuggestionFlow {
  public typealias Suggest = @Sendable (String, URL?) async throws -> CommandSuggestion

  public static let timeout: Duration = .seconds(20)
  public static var timeoutMessage: String { String(
    localized: "The AI took too long", bundle: .localized,
    comment: "Error shown on the AI suggestion card when the model times out.") }

  /// `nil` = sin tarjeta.
  public private(set) var card: SuggestionCardState?

  @ObservationIgnored private let suggest: Suggest
  @ObservationIgnored private let isCurrent: (InsertionToken) -> Bool
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var token: InsertionToken?
  @ObservationIgnored private var generation = 0

  /// `isCurrent` dice si el token sigue siendo el del prompt actual del panel; `sleep` es el
  /// reloj del tiempo límite (los tests lo sustituyen).
  public init(
    suggest: @escaping Suggest, isCurrent: @escaping (InsertionToken) -> Bool,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.suggest = suggest
    self.isCurrent = isCurrent
    self.sleep = sleep
  }

  public func request(_ text: String, token: InsertionToken, cwd: URL?) {
    task?.cancel()
    generation += 1
    let generation = generation
    self.token = token
    card = .loading
    let suggest = suggest
    let sleep = sleep
    task = Task { [weak self] in
      let outcome = await Self.race(text, cwd: cwd, suggest: suggest, sleep: sleep)
      guard !Task.isCancelled else { return }
      self?.finish(outcome, generation: generation)
    }
  }

  /// esc, cierre del panel o tarjeta descartada.
  public func cancel() {
    task?.cancel()
    task = nil
    token = nil
    card = nil
  }

  /// Escribe la sugerencia con el token de la petición y cierra la tarjeta si se insertó; si se
  /// rechaza, la tarjeta sigue abierta y el llamador muestra `failureMessage(for:)`.
  public func insert(
    _ suggestion: CommandSuggestion,
    using insertIntoPrompt: (String, InsertionToken) -> InsertResult
  ) -> InsertResult {
    guard let token else { return .stale }
    let result = insertIntoPrompt(suggestion.command, token)
    if result == .inserted { cancel() }
    return result
  }

  /// Espera a que termine la petición en curso, si hay una.
  public func settled() async {
    await task?.value
  }

  /// `nil` si se insertó: el resultado visible es el comando en el prompt.
  public static func failureMessage(for result: InsertResult) -> String? {
    switch result {
    case .inserted: nil
    case .notAtPrompt:
      String(
        localized: "Wait for the prompt to come back to insert the suggestion.", bundle: .localized,
        comment:
          "Toast shown when the AI suggestion can't be inserted because a command is running.")
    case .stale:
      String(
        localized: "The prompt has changed. Ask for the suggestion again.", bundle: .localized,
        comment: "Toast shown when the prompt changed while the AI suggestion was pending.")
    case .unsafe(let rejection):
      rejection.errorDescription
        ?? String(
          localized: "This command can’t be written to the prompt.", bundle: .localized,
          comment: "Toast shown when a suggested command is rejected for the prompt.")
    }
  }

  // MARK: - Privado

  private enum Outcome: Sendable {
    case suggestion(CommandSuggestion)
    case failure(SuggestionError)
    case timedOut
  }

  private func finish(_ outcome: Outcome, generation: Int) {
    guard generation == self.generation, let token else { return }
    task = nil
    switch outcome {
    case .suggestion(let suggestion):
      card = isCurrent(token) ? .result(suggestion) : nil
    case .failure(let error):
      card = SuggestionCardState(error: error)
    case .timedOut:
      card = .failed(Self.timeoutMessage)
    }
    if card == nil { self.token = nil }
  }

  /// Lo primero que llegue: la respuesta del modelo o el tiempo límite.
  private nonisolated static func race(
    _ text: String, cwd: URL?, suggest: @escaping Suggest,
    sleep: @escaping @Sendable (Duration) async throws -> Void
  ) async -> Outcome {
    await TimeLimit.run(
      limit: timeout, sleep: sleep,
      operation: {
        do {
          return .suggestion(try await suggest(text, cwd))
        } catch let error as SuggestionError {
          return .failure(error)
        } catch is CancellationError {
          return .failure(.cancelled)
        } catch {
          return .failure(.unknown)
        }
      }, onTimeout: { .timedOut })
  }
}
