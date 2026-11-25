import Foundation
import Testing

@testable import MacterminalCore

@Suite(.language("en")) struct DurationFormatTests {
  private static let english = Locale(identifier: "en_US")

  @Test(arguments: [
    (Duration.milliseconds(400), "0.4 s"),
    (.milliseconds(3_900), "3.9 s"),
    (.milliseconds(3_949), "3.9 s"),
    (.milliseconds(3_950), "4.0 s"),
    (.zero, "0.0 s"),
    (.milliseconds(59_960), "1 min 0 s"),
    (.seconds(72), "1 min 12 s"),
    (.seconds(3_599), "59 min 59 s"),
    (.seconds(3_600), "1 h 0 min"),
    (.seconds(7_380), "2 h 3 min"),
    (.seconds(-5), "0.0 s"),
  ])
  func short(_ duration: Duration, _ expected: String) {
    #expect(DurationFormat.short(duration, locale: Self.english) == expected)
  }

  @Test(arguments: [
    (Duration.milliseconds(3_900), "3.9 seconds"),
    (.seconds(72), "1 minute 12 seconds"),
    (.seconds(121), "2 minutes 1 second"),
    (.seconds(3_660), "1 hour 1 minute"),
    (.seconds(7_380), "2 hours 3 minutes"),
  ])
  func spoken(_ duration: Duration, _ expected: String) {
    #expect(DurationFormat.spoken(duration, locale: Self.english) == expected)
  }

  @Test func hugeDurationsDoNotOverflow() {
    #expect(DurationFormat.short(.seconds(Int64.max)).hasSuffix("min"))
    #expect(DurationFormat.spoken(.seconds(Int64.max)).contains("hour"))
  }
}
