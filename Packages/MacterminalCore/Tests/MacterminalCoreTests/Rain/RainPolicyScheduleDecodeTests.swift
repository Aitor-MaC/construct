import Foundation
import Testing

@testable import MacterminalCore

@Suite struct RainPausePolicyTests {
  struct Case: Sendable, CustomTestStringConvertible {
    var occluded = false, windowActive = true, appActive = true, lowPower = false
    var reduceMotion = false, contrast = false
    var intensity = Intensity.equilibrado
    var fullscreenPower = false
    var expected: RainRunState
    var testDescription: String { "\(self)" }
  }

  static let cases: [Case] = [
    .init(expected: .running(fps: 30)),
    .init(intensity: .sutil, expected: .running(fps: 30)),
    .init(intensity: .inmersivo, expected: .running(fps: 30)),
    .init(intensity: .inmersivo, fullscreenPower: true, expected: .running(fps: 60)),
    .init(intensity: .equilibrado, fullscreenPower: true, expected: .running(fps: 30)),
    .init(intensity: .sutil, fullscreenPower: true, expected: .running(fps: 30)),
    .init(occluded: true, expected: .frozen),
    .init(windowActive: false, expected: .frozen),
    .init(appActive: false, expected: .frozen),
    .init(lowPower: true, intensity: .inmersivo, fullscreenPower: true, expected: .frozen),
    .init(reduceMotion: true, expected: .frozen),
    .init(reduceMotion: true, intensity: .inmersivo, expected: .frozen),
    .init(reduceMotion: true, intensity: .sutil, expected: .hidden),
    .init(occluded: true, reduceMotion: true, expected: .frozen),
    .init(contrast: true, expected: .hidden),
    .init(contrast: true, intensity: .inmersivo, fullscreenPower: true, expected: .hidden),
    .init(occluded: true, contrast: true, expected: .hidden),
    .init(reduceMotion: true, contrast: true, expected: .hidden),
  ]

  @Test(arguments: cases)
  func truthTable(_ c: Case) {
    let state = RainPausePolicy.state(
      windowOccluded: c.occluded, windowActive: c.windowActive, appActive: c.appActive,
      lowPower: c.lowPower, reduceMotion: c.reduceMotion, increaseContrast: c.contrast,
      intensity: c.intensity, fullScreenOnPower: c.fullscreenPower)
    #expect(state == c.expected)
  }
}

@Suite struct DecodeTextTests {
  @Test func progressOneReturnsFinalExactly() {
    var rng = SplitMix64(seed: 1)
    #expect(DecodeText.frame(final: "3,9 s", progress: 1, using: &rng) == "3,9 s")
    #expect(DecodeText.frame(final: "3,9 s", progress: 7, using: &rng) == "3,9 s")
  }

  @Test(arguments: ["", "abc", "3,9 s", "añejo café", "🙂🇪🇸x", "e\u{301}ñ", "a b  c"])
  func lengthIsPreserved(text: String) {
    var rng = SplitMix64(seed: 2)
    for progress in [-1, 0, 0.5, 0.99, 1, Double.nan, .infinity] {
      let out = DecodeText.frame(final: text, progress: progress, using: &rng)
      #expect(out.count == text.count)
    }
  }

  @Test func halfProgressFixesPrefixAndKeepsSpaces() {
    var rng = SplitMix64(seed: 3)
    let out = DecodeText.frame(final: "ab cdefgh", progress: 0.5, using: &rng)
    #expect(String(out.prefix(4)) == "ab c")
    #expect(Array(out)[2] == " ")
    let zero = DecodeText.frame(final: "ab cd", progress: 0, using: &rng)
    #expect(Array(zero)[2] == " ")
    let allowed = Set(RainGlyphs.all)
    #expect(Array(zero).enumerated().allSatisfy { $0.offset == 2 || allowed.contains($0.element) })
  }

  @Test func deterministicWithSameSeed() {
    var a = SplitMix64(seed: 5)
    var b = SplitMix64(seed: 5)
    #expect(
      DecodeText.frame(final: "hello world", progress: 0.3, using: &a)
        == DecodeText.frame(final: "hello world", progress: 0.3, using: &b))
  }
}
