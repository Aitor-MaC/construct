import Foundation

public enum RainRunState: Equatable, Sendable {
  case running(fps: Int)
  case frozen
  case hidden
}

public enum RainPausePolicy {
  public static func state(
    windowOccluded: Bool, windowActive: Bool, appActive: Bool, lowPower: Bool,
    reduceMotion: Bool, increaseContrast: Bool, intensity: Intensity, fullScreenOnPower: Bool
  ) -> RainRunState {
    if increaseContrast { return .hidden }
    if reduceMotion { return intensity == .sutil ? .hidden : .frozen }
    if windowOccluded || !windowActive || !appActive || lowPower { return .frozen }
    let profile = intensity.profile
    let fps =
      intensity == .inmersivo && fullScreenOnPower
      ? profile.fullscreenPoweredFramesPerSecond : profile.framesPerSecond
    return .running(fps: fps)
  }
}
