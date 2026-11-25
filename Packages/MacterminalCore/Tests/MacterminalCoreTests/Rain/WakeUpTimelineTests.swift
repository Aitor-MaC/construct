import Foundation
import Testing

@testable import MacterminalCore

@Suite struct WakeUpTimelineTests {
  let timeline = WakeUpTimeline(givenName: "Aitor", reduceMotion: false)
  let full = ["Wake up, Aitor…", "The Matrix has you."]

  @Test func linesUseTheGivenName() {
    #expect(timeline.lines == full)
  }

  @Test func missingNameDropsTheVocative() {
    #expect(WakeUpTimeline(givenName: nil, reduceMotion: false).lines.first == "Wake up…")
    #expect(WakeUpTimeline(givenName: "  ", reduceMotion: false).lines.first == "Wake up…")
  }

  @Test func typesTheFirstLineAt62MillisecondsPerCharacter() {
    #expect(timeline.phase(at: .zero) == .showing(lines: ["W"]))
    #expect(timeline.phase(at: .milliseconds(61)) == .showing(lines: ["W"]))
    #expect(timeline.phase(at: .milliseconds(62)) == .showing(lines: ["Wa"]))
    // 15 caracteres: el último aparece en 14 × 62 = 868 ms.
    #expect(timeline.phase(at: .milliseconds(867)) == .showing(lines: ["Wake up, Aitor"]))
    #expect(timeline.phase(at: .milliseconds(868)) == .showing(lines: ["Wake up, Aitor…"]))
  }

  @Test func pausesBeforeTypingTheSecondLine() {
    #expect(timeline.phase(at: .milliseconds(1387)) == .showing(lines: ["Wake up, Aitor…"]))
    #expect(timeline.phase(at: .milliseconds(1388)) == .showing(lines: ["Wake up, Aitor…", "T"]))
    // 19 caracteres: 1388 + 18 × 62 = 2504 ms.
    #expect(timeline.phase(at: .milliseconds(2503)) != .showing(lines: full))
    #expect(timeline.phase(at: .milliseconds(2504)) == .showing(lines: full))
  }

  @Test func holdsThenFadesOutIn220Milliseconds() {
    #expect(timeline.phase(at: .milliseconds(3603)) == .showing(lines: full))
    #expect(timeline.phase(at: .milliseconds(3604)) == .fadingOut(lines: full))
    #expect(timeline.phase(at: .milliseconds(3823)) == .fadingOut(lines: full))
    #expect(timeline.phase(at: .milliseconds(3824)) == .finished)
    #expect(timeline.phase(at: .seconds(60)) == .finished)
    #expect(WakeUpTimeline.fadeOut == .milliseconds(220))
  }

  @Test func nextChangeWalksEveryKeyframeAndEnds() {
    var elapsed = Duration.zero
    var seen: [WakeUpTimeline.Phase] = [timeline.phase(at: elapsed)]
    while let next = timeline.nextChange(after: elapsed) {
      #expect(next > elapsed)
      elapsed = next
      seen.append(timeline.phase(at: elapsed))
    }
    #expect(elapsed == .milliseconds(3824))
    #expect(seen.last == .finished)
    // 15 + 19 pasos de tecleo, el fundido y el final.
    #expect(seen.count == 15 + 19 + 2)
  }

  @Test func reduceMotionShowsTheFullTextFor1800Milliseconds() {
    let reduced = WakeUpTimeline(givenName: "Aitor", reduceMotion: true)
    #expect(reduced.phase(at: .zero) == .showing(lines: full))
    #expect(reduced.phase(at: .milliseconds(1799)) == .showing(lines: full))
    #expect(reduced.phase(at: .milliseconds(1800)) == .finished)
    #expect(reduced.nextChange(after: .zero) == .milliseconds(1800))
    #expect(reduced.nextChange(after: .milliseconds(1800)) == nil)
  }

  @Test func negativeElapsedIsTheFirstKeyframe() {
    #expect(timeline.phase(at: .milliseconds(-5)) == .showing(lines: ["W"]))
    #expect(timeline.nextChange(after: .milliseconds(-5)) == .zero)
  }
}
