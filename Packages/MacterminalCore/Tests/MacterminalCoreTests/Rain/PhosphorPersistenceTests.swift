import Testing

@testable import MacterminalCore

@Suite struct PhosphorPersistenceTests {
  let a = GridPosition(col: 3, row: 4)
  let b = GridPosition(col: 4, row: 4)

  private func ghost(
    _ from: GridPosition?, _ to: GridPosition?, _ intensity: Intensity = .equilibrado,
    reduceMotion: Bool = false, increaseContrast: Bool = false
  ) -> GridPosition? {
    PhosphorPersistence.ghostCell(
      from: from, to: to, intensity: intensity, reduceMotion: reduceMotion,
      increaseContrast: increaseContrast)
  }

  @Test func leavesAGhostInThePreviousCell() {
    #expect(ghost(a, b) == a)
    #expect(ghost(a, nil, .inmersivo) == a)
  }

  @Test func noGhostWithoutMovementOrPreviousCell() {
    #expect(ghost(a, a) == nil)
    #expect(ghost(nil, b) == nil)
  }

  @Test(arguments: [
    (Intensity.sutil, false, false),
    (Intensity.equilibrado, true, false),
    (Intensity.inmersivo, true, false),
    (Intensity.inmersivo, false, true),
  ])
  func disabledInSutilReduceMotionAndIncreaseContrast(
    intensity: Intensity, reduceMotion: Bool, increaseContrast: Bool
  ) {
    #expect(
      ghost(a, b, intensity, reduceMotion: reduceMotion, increaseContrast: increaseContrast) == nil)
  }

  @Test func fadeConstantsMatchTheDesign() {
    #expect(PhosphorPersistence.startAlpha == 0.55)
    #expect(PhosphorPersistence.fade == .milliseconds(140))
  }
}
