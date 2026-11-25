import Testing

@testable import MacterminalCore

@Suite("GreetingName")
struct GreetingNameTests {
  @Test func stripsBidiControlsAndOuterSpaces() {
    #expect(GreetingName.sanitize("  Ne\u{202E}o\n ") == "Neo")
  }

  @Test func blankBecomesNil() {
    #expect(GreetingName.sanitize("   ") == nil)
    #expect(GreetingName.sanitize("") == nil)
    #expect(GreetingName.sanitize("\u{200B}\u{2066}\t\n") == nil)
  }

  @Test func limitsToThirtyTwoGraphemes() {
    let forty = String(repeating: "a", count: 40)
    #expect(GreetingName.sanitize(forty) == String(repeating: "a", count: 32))
    // Grafemas, no escalares: cada «é» descompuesta son dos escalares y cuenta como uno.
    let decomposed = String(repeating: "e\u{301}", count: 40)
    #expect(GreetingName.sanitize(decomposed)?.count == 32)
  }

  @Test func cutAtASpaceLeavesNoTrailingSpace() {
    let raw = String(repeating: "a", count: 31) + " bcdef"
    #expect(GreetingName.sanitize(raw) == String(repeating: "a", count: 31))
  }

  @Test func removesZeroWidthAndControlCharacters() {
    #expect(GreetingName.sanitize("N\u{200B}e\u{200D}o\u{FEFF}") == "Neo")
    #expect(GreetingName.sanitize("Ne\u{1B}[31mo") == "Ne[31mo")
    #expect(GreetingName.sanitize("\u{2067}Trinity\u{2069}") == "Trinity")
  }

  @Test func lineBreaksAndInnerRunsCollapseToOneSpace() {
    #expect(GreetingName.sanitize("Thomas\nA.   Anderson") == "Thomas A. Anderson")
    #expect(GreetingName.sanitize("Mr.\u{2028}\tSmith") == "Mr. Smith")
  }

  @Test func keepsAccentsAndNonLatinNames() {
    #expect(GreetingName.sanitize("Aitor García") == "Aitor García")
    #expect(GreetingName.sanitize("ネオ") == "ネオ")
  }

  @Test func resolvePrefersConfiguredName() {
    #expect(GreetingName.resolve(configured: " Neo ", systemGivenName: "Aitor") == "Neo")
  }

  @Test func resolveFallsBackToSanitizedSystemName() {
    #expect(GreetingName.resolve(configured: nil, systemGivenName: "Ai\u{202E}tor") == "Aitor")
    #expect(GreetingName.resolve(configured: "  ", systemGivenName: "Aitor") == "Aitor")
  }

  @Test func resolveWithoutAnyNameIsNil() {
    #expect(GreetingName.resolve(configured: nil, systemGivenName: nil) == nil)
    #expect(GreetingName.resolve(configured: "\u{200B}", systemGivenName: " ") == nil)
  }
}

@Suite("OnboardingPolicy")
struct OnboardingPolicyTests {
  @Test(arguments: [
    (false, false, true),
    (true, false, false),
    (false, true, false),
    (true, true, false),
  ])
  func asksOnlyWithoutNameAndWithoutFlag(hasName: Bool, completed: Bool, expected: Bool) {
    #expect(
      OnboardingPolicy.shouldAsk(hasConfiguredName: hasName, completedFlag: completed) == expected)
  }
}
