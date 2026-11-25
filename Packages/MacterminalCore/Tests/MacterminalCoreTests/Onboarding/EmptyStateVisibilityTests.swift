import Testing

@testable import MacterminalCore

@Suite struct EmptyStateVisibilityTests {
  @Test func showsAtTheFirstPromptWhileNoCommandWasEverRun() {
    #expect(
      EmptyStateVisibility.shouldShow(
        hasRunFirstCommand: false, promptGeneration: 1, bannerVisible: false))
  }

  @Test func neverShowsOnceACommandRanOrItWasDismissed() {
    #expect(
      !EmptyStateVisibility.shouldShow(
        hasRunFirstCommand: true, promptGeneration: 1, bannerVisible: false))
  }

  @Test func waitsForTheFirstAuthenticatedPrompt() {
    #expect(
      !EmptyStateVisibility.shouldShow(
        hasRunFirstCommand: false, promptGeneration: 0, bannerVisible: false))
  }

  @Test func yieldsToTheIntegrationBanner() {
    #expect(
      !EmptyStateVisibility.shouldShow(
        hasRunFirstCommand: false, promptGeneration: 1, bannerVisible: true))
  }
}
