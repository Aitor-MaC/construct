import Testing

@testable import MacterminalTerminal

@Suite(.language("en")) struct StartupFailurePolicyTests {
  @Test func integratedShellThatNeverReachedAPromptKeepsThePaneOpen() {
    #expect(
      StartupFailurePolicy.keepsPaneOpen(
        integrationAvailable: true, sawAuthenticatedPrompt: false, uptime: .seconds(30)))
  }

  @Test func integratedShellExitingAfterItsFirstPromptCloses() {
    #expect(
      !StartupFailurePolicy.keepsPaneOpen(
        integrationAvailable: true, sawAuthenticatedPrompt: true, uptime: .milliseconds(100)))
  }

  @Test(arguments: [
    (Duration.milliseconds(1999), true),
    (.seconds(2), false),
    (.seconds(3), false),
  ])
  func shellWithoutIntegrationUsesTheTwoSecondRule(uptime: Duration, keepsOpen: Bool) {
    #expect(
      StartupFailurePolicy.keepsPaneOpen(
        integrationAvailable: false, sawAuthenticatedPrompt: false, uptime: uptime) == keepsOpen)
  }

  @Test func exitCodeTextUsesADashWhenUnknown() {
    #expect(StartupFailurePolicy.message(exitCode: 1) == "The shell exited at launch (code 1)")
    #expect(StartupFailurePolicy.message(exitCode: nil) == "The shell exited at launch (code —)")
  }
}
