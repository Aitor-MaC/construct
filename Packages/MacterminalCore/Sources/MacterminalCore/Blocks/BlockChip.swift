import Foundation

/// Texto y estado del chip de salida de un bloque. Lo que no se conoce (`exitCode` o `duration`
/// en `nil`) se muestra "—", nunca 0.
public struct BlockChip: Sendable, Equatable {
  public enum Tone: Sendable { case success, failure, unknown, running }

  /// Desde aquí un comando cuenta como largo: su chip se decodifica y, en marcha, muestra progreso.
  public static let longCommand: Duration = .seconds(2)
  static let unavailable = "—"

  public let tone: Tone
  public let status: String
  public let duration: String
  public let decodes: Bool
  public let showsProgress: Bool

  public init(tone: Tone, status: String, duration: String, decodes: Bool, showsProgress: Bool) {
    self.tone = tone
    self.status = status
    self.duration = duration
    self.decodes = decodes
    self.showsProgress = showsProgress
  }

  public init(block: CommandBlock, now: ContinuousClock.Instant) {
    guard block.state == .finished else {
      let elapsed = block.startedInstant.map { now - $0 }
      self.init(
        tone: .running, status: "", duration: Self.text(elapsed), decodes: false,
        showsProgress: elapsed.map { $0 > Self.longCommand } ?? false)
      return
    }
    let (tone, status): (Tone, String) =
      switch block.exitCode {
      case .none: (.unknown, Self.unavailable)
      case 0: (.success, "✓")
      case .some(let code): (.failure, "✗ \(code)")
      }
    self.init(
      tone: tone, status: status, duration: Self.text(block.duration),
      decodes: tone != .unknown && (block.duration.map { $0 >= Self.longCommand } ?? false),
      showsProgress: false)
  }

  private static func text(_ duration: Duration?) -> String {
    duration.map { DurationFormat.short($0) } ?? unavailable
  }
}
