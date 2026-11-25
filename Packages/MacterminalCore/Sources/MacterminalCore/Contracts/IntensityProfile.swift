import Foundation

public struct IntensityProfile: Sendable, Equatable {
  public let accentGlowRadius: Double
  public let accentGlowAlpha: Double
  public let textGlowRadius: Double
  public let textGlowAlpha: Double
  public let activeColumnFraction: Double
  /// Cells per second.
  public let speed: ClosedRange<Double>
  public let trailLength: ClosedRange<Int>
  public let headAlpha: Double
  public let trailAlpha: Double
  public let mutationRate: Double
  public let typingAlphaMultiplier: Double
  public let scanlines: Bool
  public let vignetteAlpha: Double
  public let wakeUp: Bool
  public var textRowAlphaCap: Double { 0.10 }
  public var framesPerSecond: Int { 30 }
  public var fullscreenPoweredFramesPerSecond: Int { wakeUp ? 60 : 30 }
  public var typingFadeOut: Duration { .milliseconds(200) }
  public var typingIdleDelay: Duration { .seconds(6) }
  public var typingFadeIn: Duration { .milliseconds(600) }
  public var scanlinePeriodPixels: Int { 3 }
  public var scanlineAlpha: Double { scanlines ? 0.16 : 0 }
}
