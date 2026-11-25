import Testing

@testable import MacterminalCore

@MainActor @Suite struct InsertionTokenTests {
  private func harnessAtPrompt() throws -> (TrackerHarness, InsertionToken) {
    let harness = TrackerHarness()
    harness.feed("A", row: 0)
    harness.feed("B", row: 0)
    let token = try #require(harness.tracker.insertionToken())
    #expect(harness.tracker.isCurrent(token))
    return (harness, token)
  }

  @Test func tokenCarriesSessionAndGeneration() throws {
    let (harness, token) = try harnessAtPrompt()
    #expect(token.session == harness.session)
    #expect(token.promptGeneration == harness.tracker.promptGeneration)
  }

  @Test func commandStartInvalidatesTheToken() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.feed("C", ProtocolFixture.base64("ls"), row: 1)
    #expect(!harness.tracker.isCurrent(token))
    #expect(harness.tracker.insertionToken() == nil)
  }

  @Test func newPromptInvalidatesTheOldTokenAndIssuesANewOne() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.feed("A", row: 1)
    #expect(!harness.tracker.isCurrent(token))
    let fresh = try #require(harness.tracker.insertionToken())
    #expect(fresh.promptGeneration == token.promptGeneration + 1)
    #expect(harness.tracker.isCurrent(fresh))
  }

  @Test func alternateScreenSuspendsTheToken() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.tracker.setAlternateScreen(true)
    #expect(!harness.tracker.isCurrent(token))
    #expect(harness.tracker.insertionToken() == nil)
  }

  @Test func resetInvalidatesTheToken() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.tracker.reset()
    #expect(!harness.tracker.isCurrent(token))
    #expect(harness.tracker.insertionToken() == nil)
  }

  @Test func endSessionInvalidatesTheTokenAndIgnoresLaterMarks() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.tracker.endSession()
    #expect(!harness.tracker.isCurrent(token))
    #expect(!harness.tracker.isAtPrompt)
    harness.feed("A", row: 1)
    #expect(harness.tracker.insertionToken() == nil)
  }

  @Test func restartingThePaneInvalidatesTheOldToken() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.tracker.beginSession(SessionID())
    #expect(!harness.tracker.isCurrent(token))
    harness.feed("A", row: 0)
    #expect(!harness.tracker.isCurrent(token))
    #expect(harness.tracker.insertionToken() != nil)
  }

  @Test func desynchronizeInvalidatesTheToken() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.tracker.desynchronize()
    #expect(!harness.tracker.isCurrent(token))
  }

  @Test func twoSessionsWithTheSameGenerationRejectEachOthersTokens() throws {
    let (first, firstToken) = try harnessAtPrompt()
    let (second, secondToken) = try harnessAtPrompt()
    #expect(firstToken.promptGeneration == secondToken.promptGeneration)
    #expect(!first.tracker.isCurrent(secondToken))
    #expect(!second.tracker.isCurrent(firstToken))
  }

  @Test func generationNeverRepeatsAcrossResetAndRestart() throws {
    let (harness, token) = try harnessAtPrompt()
    harness.tracker.reset()
    harness.tracker.beginSession(harness.session)
    harness.feed("A", row: 0)
    let next = try #require(harness.tracker.insertionToken())
    #expect(next.promptGeneration > token.promptGeneration)
    #expect(!harness.tracker.isCurrent(token))
  }
}
