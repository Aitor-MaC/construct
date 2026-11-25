import CoreGraphics
import Testing

@testable import MacterminalCore

@Suite struct QuakeSlideTests {
  /// Two displays stacked vertically: the lower one is the target, the upper one must stay clean.
  private let lowerVisible = CGRect(x: 0, y: 0, width: 1440, height: 875)
  private let upperScreen = CGRect(x: 0, y: 900, width: 1440, height: 900)

  @Test func frameIsAnchoredToTheTopOfTheVisibleArea() {
    let slide = QuakeSlide(visible: lowerVisible, heightFraction: 0.4)
    #expect(slide.frame == CGRect(x: 0, y: 525, width: 1440, height: 350))
  }

  @Test func frameNeverLeavesTheTargetScreen() {
    let slide = QuakeSlide(visible: lowerVisible, heightFraction: 0.4)
    #expect(lowerVisible.contains(slide.frame))
    #expect(!slide.frame.intersects(upperScreen))
  }

  @Test func hiddenOffsetPushesTheContentFullyOutOfTheFrame() {
    let slide = QuakeSlide(visible: lowerVisible, heightFraction: 0.4)
    let hiddenContent = CGRect(origin: .zero, size: slide.frame.size)
      .offsetBy(dx: 0, dy: slide.hiddenContentOffset)
    #expect(!hiddenContent.intersects(CGRect(origin: .zero, size: slide.frame.size)))
  }

  @Test func heightIsRoundedToWholePoints() {
    let slide = QuakeSlide(
      visible: CGRect(x: 0, y: 0, width: 800, height: 601), heightFraction: 0.4)
    #expect(slide.frame.height == 240)
    #expect(slide.frame.maxY == 601)
  }
}
