import Foundation
import FoundationModels
import os

// MARK: - Tipos intermedios (inyectables)

/// Motivos por los que el modelo del sistema no está disponible, desacoplados de FoundationModels.
public enum ModelAvailabilityReason: Sendable, Equatable {
  case deviceNotEligible
  case appleIntelligenceNotEnabled
  case modelNotReady
  case other

  /// El motivo puede resolverse sin reiniciar la app (descarga en curso o activarlo en Ajustes del
  /// Sistema), así que la interfaz vuelve a comprobar periódicamente y ofrece abrir esos ajustes.
  public var isTransient: Bool {
    self == .modelNotReady || self == .appleIntelligenceNotEnabled
  }
}

public enum ModelAvailability: Sendable, Equatable {
  case available
  case unavailable(ModelAvailabilityReason)
}

/// Fallos de generación, desacoplados de `LanguageModelError` y compañía para poder probarlos.
public enum ModelFailure: Sendable, Equatable {
  case guardrailViolation
  case exceededContextWindowSize
  case rateLimited
  case concurrentRequests
  case unsupportedLanguageOrLocale
  case modelAssetsUnavailable
  case unknown
}

/// Error que un `SuggestionBackend` lanza para describir un fallo del modelo.
public struct ModelFailureError: Error, Sendable, Equatable {
  public let failure: ModelFailure
  public init(_ failure: ModelFailure) { self.failure = failure }
}

/// Salida cruda del modelo, antes de sanear.
public struct RawSuggestion: Sendable, Equatable {
  public let command: String
  public let explanation: String
  public init(command: String, explanation: String) {
    self.command = command
    self.explanation = explanation
  }
}

/// Fuente de sugerencias. La real usa Foundation Models; los tests inyectan una simulada.
public protocol SuggestionBackend: Sendable {
  func availability() -> ModelAvailability
  /// Recibe solo la petición y la carpeta actual (I11): nunca salida del terminal.
  func generate(request: String, cwd: String?) async throws -> RawSuggestion
}

public enum SuggestionError: Error, LocalizedError, Equatable, Sendable {
  case unavailable(reason: String)
  case cancelled
  case emptyRequest
  case invalidOutput
  case guardrailViolation
  case exceededContextWindowSize
  case rateLimited
  case concurrentRequests
  case unsupportedLanguageOrLocale
  case modelAssetsUnavailable
  case unknown

  public init(failure: ModelFailure) {
    switch failure {
    case .guardrailViolation: self = .guardrailViolation
    case .exceededContextWindowSize: self = .exceededContextWindowSize
    case .rateLimited: self = .rateLimited
    case .concurrentRequests: self = .concurrentRequests
    case .unsupportedLanguageOrLocale: self = .unsupportedLanguageOrLocale
    case .modelAssetsUnavailable: self = .modelAssetsUnavailable
    case .unknown: self = .unknown
    }
  }

  public var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .cancelled:
      String(
        localized: "Suggestion cancelled.", bundle: .localized,
        comment: "AI suggestion error: the request was cancelled.")
    case .emptyRequest:
      String(
        localized: "Type what you want to do to ask for a suggestion.", bundle: .localized,
        comment: "AI suggestion error: the request after # was empty.")
    case .invalidOutput:
      String(
        localized: "The model didn’t return a usable command. Try rewording the request.",
        bundle: .localized, comment: "AI suggestion error.")
    case .guardrailViolation:
      String(
        localized:
          "The model declined the request because of its safety filters. Try rewording it.",
        bundle: .localized, comment: "AI suggestion error.")
    case .exceededContextWindowSize:
      String(
        localized: "The request is too long for the model. Shorten it and try again.",
        bundle: .localized, comment: "AI suggestion error.")
    case .rateLimited:
      String(
        localized: "The model is rate limiting requests. Wait a moment and try again.",
        bundle: .localized, comment: "AI suggestion error.")
    case .concurrentRequests:
      String(
        localized: "A suggestion is already in progress. Wait for it to finish.", bundle: .localized,
        comment: "AI suggestion error.")
    case .unsupportedLanguageOrLocale:
      String(
        localized: "The model doesn’t support the language of the request.", bundle: .localized,
        comment: "AI suggestion error.")
    case .modelAssetsUnavailable:
      String(
        localized: "The Apple Intelligence model isn’t downloaded on this Mac yet.",
        bundle: .localized, comment: "AI suggestion error.")
    case .unknown:
      String(
        localized: "The suggestion couldn’t be generated. Try again.", bundle: .localized,
        comment: "AI suggestion error.")
    }
  }
}

// MARK: - CommandSuggester

/// Sugiere un comando zsh a partir de una petición en lenguaje natural, todo on-device y sin red.
public struct CommandSuggester: Sendable {
  /// Cota de la petición enviada al modelo (evita desbordar su ventana de contexto).
  static let maxRequestCharacters = 2000
  static let maxCommandCharacters = 500
  /// Cota de escalares procesados al sanear, para acotar entradas hostiles (marcas combinantes, etc.).
  static let maxScalarsScanned = 4000

  private let backend: any SuggestionBackend
  private let log = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "ai")

  public init(backend: any SuggestionBackend = SystemModelBackend()) {
    self.backend = backend
  }

  public func availability() -> SuggestionAvailability {
    availabilityWithReason().availability
  }

  /// Igual que `availability()`, más el motivo en bruto cuando no está disponible.
  public func availabilityWithReason() -> (availability: SuggestionAvailability, reason: ModelAvailabilityReason?) {
    switch backend.availability() {
    case .available:
      return (.available, nil)
    case .unavailable(let reason):
      log.info("AI unavailable: \(String(describing: reason), privacy: .public)")
      return (.unavailable(reason: Self.message(for: reason)), reason)
    }
  }

  static func message(for reason: ModelAvailabilityReason) -> String {
    switch reason {
    case .deviceNotEligible:
      String(
        localized: "This Mac doesn’t support Apple Intelligence.", bundle: .localized,
        comment: "Reason the AI suggestions are unavailable.")
    case .appleIntelligenceNotEnabled:
      String(
        localized: "Apple Intelligence is turned off. Turn it on in System Settings.",
        bundle: .localized, comment: "Reason the AI suggestions are unavailable.")
    case .modelNotReady:
      String(
        localized: "The Apple Intelligence model is still downloading. Try again later.",
        bundle: .localized, comment: "Reason the AI suggestions are unavailable.")
    case .other:
      String(
        localized: "The Apple Intelligence model isn’t available right now.", bundle: .localized,
        comment: "Reason the AI suggestions are unavailable.")
    }
  }

  /// Una `LanguageModelSession` nueva por petición (en el backend real). Respeta la cancelación.
  public func suggest(for request: String, cwd: URL?) async throws -> CommandSuggestion {
    try Self.throwIfCancelled()
    let text = String(
      request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRequestCharacters))
    guard !text.isEmpty else { throw SuggestionError.emptyRequest }
    if case .unavailable(let reason) = availability() {
      throw SuggestionError.unavailable(reason: reason)
    }

    let raw: RawSuggestion
    do {
      raw = try await backend.generate(request: text, cwd: cwd?.path)
    } catch let error as SuggestionError {
      throw error
    } catch let error as ModelFailureError {
      try Self.throwIfCancelled()
      log.error("AI failure: \(String(describing: error.failure), privacy: .public)")
      throw SuggestionError(failure: error.failure)
    } catch is CancellationError {
      throw SuggestionError.cancelled
    } catch {
      try Self.throwIfCancelled()
      log.error("AI failure: unknown")
      throw SuggestionError.unknown
    }
    // Una cancelación tardía no publica un resultado obsoleto.
    try Self.throwIfCancelled()
    guard
      let clean = Self.sanitize(
        CommandSuggestion(command: raw.command, explanation: raw.explanation))
    else {
      log.error("AI failure: invalid output")
      throw SuggestionError.invalidOutput
    }
    return clean
  }

  private static func throwIfCancelled() throws {
    if Task.isCancelled { throw SuggestionError.cancelled }
  }

  // MARK: - Saneado

  /// Deja el comando en una sola línea, sin controles, ESC, C1, bidi ni ancho cero, recortado y ≤ 500
  /// caracteres. `nil` si queda vacío. Se aplica siempre antes de entregar una sugerencia.
  public static func sanitize(_ suggestion: CommandSuggestion) -> CommandSuggestion? {
    guard let command = cleanLine(suggestion.command, limit: maxCommandCharacters) else {
      return nil
    }
    let explanation = suggestion.explanation.flatMap { cleanLine($0, limit: maxCommandCharacters) }
    return CommandSuggestion(command: command, explanation: explanation)
  }

  private static func cleanLine(_ input: String, limit: Int) -> String? {
    var scalars = String.UnicodeScalarView()
    var scanned = 0
    for scalar in input.unicodeScalars {
      scanned += 1
      if scanned > maxScalarsScanned { break }
      switch scalar.value {
      case 0x0A, 0x0D, 0x09, 0x0B, 0x0C, 0x85, 0x2028, 0x2029:
        scalars.append(" ")  // saltos y tabuladores pasan a espacio: nunca ejecutan ni completan
      case 0x00...0x1F, 0x7F, 0x80...0x9F,  // controles, ESC y C1
        0x061C, 0x180E, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069,
        0xFEFF, 0xFFF9...0xFFFB, 0xE0000...0xE007F:  // bidi, ancho cero y etiquetas
        continue
      default:
        scalars.append(scalar)
      }
    }
    var line = String(scalars)
      .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespaces)
    if line.count > limit {
      line = String(line.prefix(limit)).trimmingCharacters(in: .whitespaces)
    }
    return line.isEmpty ? nil : line
  }
}

// MARK: - Backend real (Foundation Models)

@Generable
struct GeneratedSuggestion {
  @Guide(
    description: "A single zsh command for macOS, on one line, without Markdown or code fences")
  var command: String
  @Guide(description: "Short explanation of what the command does, in the language of the request")
  var explanation: String
}

/// Usa el modelo del sistema. Crea una sesión nueva por petición para evitar `concurrentRequests`.
public struct SystemModelBackend: SuggestionBackend {
  static let instructions = """
    You are a command-line assistant. Reply with a single zsh command for macOS that fulfills \
    the request, without running it, without Markdown and without code blocks. The explanation is \
    one short sentence written in the same language as the request.
    """

  public init() {}

  public func availability() -> ModelAvailability {
    switch SystemLanguageModel.default.availability {
    case .available:
      return .available
    case .unavailable(let reason):
      switch reason {
      case .deviceNotEligible: return .unavailable(.deviceNotEligible)
      case .appleIntelligenceNotEnabled: return .unavailable(.appleIntelligenceNotEnabled)
      case .modelNotReady: return .unavailable(.modelNotReady)
      @unknown default: return .unavailable(.other)
      }
    @unknown default:
      return .unavailable(.other)
    }
  }

  public func generate(request: String, cwd: String?) async throws -> RawSuggestion {
    let session = LanguageModelSession(instructions: Self.instructions)
    var prompt = "Request: \(request)"
    if let cwd { prompt += "\nCurrent folder: \(cwd)" }
    do {
      let response = try await session.respond(to: prompt, generating: GeneratedSuggestion.self)
      return RawSuggestion(
        command: response.content.command, explanation: response.content.explanation)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ModelFailureError(Self.classify(error))
    }
  }

  static func classify(_ error: any Error) -> ModelFailure {
    if let error = error as? LanguageModelError {
      switch error {
      case .guardrailViolation, .refusal: return .guardrailViolation
      case .contextSizeExceeded: return .exceededContextWindowSize
      case .rateLimited: return .rateLimited
      case .unsupportedLanguageOrLocale: return .unsupportedLanguageOrLocale
      default: return .unknown
      }
    }
    if let error = error as? LanguageModelSession.Error, error == .concurrentRequests {
      return .concurrentRequests
    }
    if let error = error as? SystemLanguageModel.Error {
      switch error {
      case .assetsUnavailable: return .modelAssetsUnavailable
      @unknown default: return .unknown
      }
    }
    return .unknown
  }
}
