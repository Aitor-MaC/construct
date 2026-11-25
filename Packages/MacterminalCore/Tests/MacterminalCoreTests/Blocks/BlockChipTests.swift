import Foundation
import Testing

@testable import MacterminalCore

@MainActor @Suite struct BlockChipTests {
  private func finishedBlock(exit: String, after duration: Duration) -> (
    CommandBlock, TrackerHarness
  ) {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("B", row: 0)
    harness.feed("C", ProtocolFixture.base64("swift test"), row: 1)
    harness.clocks.elapsed = duration
    harness.feed("D", exit, row: 4)
    return (harness.tracker.blocks[0], harness)
  }

  @Test func successShowsACheckAndTheDurationAndDecodesFromTwoSeconds() {
    let (block, harness) = finishedBlock(exit: "0", after: .milliseconds(3_900))
    let chip = BlockChip(block: block, now: harness.clocks.instant)
    #expect(
      chip
        == BlockChip(
          tone: .success, status: "✓", duration: "3\(Locale.current.decimalSeparator ?? ".")9 s",
          decodes: true, showsProgress: false))
  }

  @Test func failureShowsTheExitCodeAndShortCommandsDoNotDecode() {
    let (block, harness) = finishedBlock(exit: "1", after: .milliseconds(1_200))
    let chip = BlockChip(block: block, now: harness.clocks.instant)
    #expect(
      chip
        == BlockChip(
          tone: .failure, status: "✗ 1", duration: "1\(Locale.current.decimalSeparator ?? ".")2 s",
          decodes: false, showsProgress: false))
  }

  @Test func unknownExitCodeAndDurationAreShownAsDashNeverZero() {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("B", row: 0)
    harness.feed("C", ProtocolFixture.base64("vim"), row: 1)
    // Llega otro prompt sin D: el bloque se cierra sin código.
    harness.feed("A", row: 5)
    let block = harness.tracker.blocks[0]
    #expect(block.exitCode == nil)
    let chip = BlockChip(block: block, now: harness.clocks.instant)
    #expect(chip.tone == .unknown)
    #expect(chip.status == "—")
    #expect(chip.decodes == false)
  }

  @Test func finishedWithoutDurationShowsDash() {
    let block = CommandBlock(
      command: "ls", promptAnchor: RowAnchor(id: 0), exitCode: 0, state: .finished)
    let chip = BlockChip(block: block, now: ContinuousClock.now)
    #expect(chip.status == "✓")
    #expect(chip.duration == "—")
    #expect(chip.decodes == false)
  }

  @Test(arguments: [
    (Duration.milliseconds(1_500), "1#5 s", false), (.milliseconds(2_100), "2#1 s", true),
  ])
  func runningShowsLiveDurationAndProgressOnlyAfterTwoSeconds(
    elapsed: Duration, text: String, progress: Bool
  ) {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("B", row: 0)
    harness.feed("C", ProtocolFixture.base64("make"), row: 1)
    let chip = BlockChip(
      block: harness.tracker.blocks[0], now: harness.clocks.instant.advanced(by: elapsed))
    // The chip formats with the region of the machine; "#" stands for its decimal separator.
    let expected = text.replacingOccurrences(of: "#", with: Locale.current.decimalSeparator ?? ".")
    #expect(
      chip
        == BlockChip(
          tone: .running, status: "", duration: expected, decodes: false, showsProgress: progress))
  }
}
