import Foundation

/// Temporización del saludo "Wake up" de Inmersivo como lista de fotogramas clave.
public struct WakeUpTimeline: Sendable {
  public enum Phase: Sendable, Equatable {
    /// Texto visible por línea (la última puede estar a medio teclear).
    case showing(lines: [String])
    case fadingOut(lines: [String])
    case finished
  }

  public static let characterInterval: Duration = .milliseconds(62)
  public static let linePause: Duration = .milliseconds(520)
  public static let hold: Duration = .milliseconds(1100)
  public static let fadeOut: Duration = .milliseconds(220)
  public static let reducedMotionHold: Duration = .milliseconds(1800)

  public let lines: [String]
  private let keyframes: [(time: Duration, phase: Phase)]

  public init(givenName: String?, reduceMotion: Bool) {
    let name = givenName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    lines = [name.isEmpty ? "Wake up…" : "Wake up, \(name)…", "The Matrix has you."]
    keyframes = reduceMotion ? Self.reducedKeyframes(lines) : Self.typedKeyframes(lines)
  }

  public func phase(at elapsed: Duration) -> Phase {
    keyframes.last(where: { $0.time <= elapsed })?.phase ?? keyframes[0].phase
  }

  /// Momento del siguiente cambio de fase posterior a `elapsed`; `nil` cuando ya terminó.
  public func nextChange(after elapsed: Duration) -> Duration? {
    keyframes.first(where: { $0.time > elapsed })?.time
  }

  private static func reducedKeyframes(_ lines: [String]) -> [(time: Duration, phase: Phase)] {
    [(.zero, .showing(lines: lines)), (reducedMotionHold, .finished)]
  }

  private static func typedKeyframes(_ lines: [String]) -> [(time: Duration, phase: Phase)] {
    var frames: [(time: Duration, phase: Phase)] = []
    var time = Duration.zero
    for (index, line) in lines.enumerated() {
      if index > 0 { time += linePause - characterInterval }
      let done = Array(lines.prefix(index))
      for count in 1...line.count {
        if !(index == 0 && count == 1) { time += characterInterval }
        frames.append((time, .showing(lines: done + [String(line.prefix(count))])))
      }
    }
    time += hold
    frames.append((time, .fadingOut(lines: lines)))
    frames.append((time + fadeOut, .finished))
    return frames
  }
}
