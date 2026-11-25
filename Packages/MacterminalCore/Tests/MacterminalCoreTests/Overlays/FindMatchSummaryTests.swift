import Testing

@testable import MacterminalCore

@Suite(.language("en")) struct FindMatchSummaryTests {
  @Test func currentMatchAmongSeveral() {
    let summary = FindMatchSummary(index: 3, total: 12, limit: 1000)
    #expect(summary.label == "3 of 12")
    #expect(summary.hasMatches)
  }

  @Test func noMatchesNeverReadsZeroOfZero() {
    let summary = FindMatchSummary(index: 0, total: 0, limit: 1000)
    #expect(summary.label == "No matches")
    #expect(!summary.hasMatches)
  }

  @Test func matchesWithoutCurrentShowTheCount() {
    #expect(FindMatchSummary(index: 0, total: 5, limit: 1000).label == "5 matches")
    #expect(FindMatchSummary(index: 0, total: 1, limit: 1000).label == "1 match")
  }

  @Test func totalAtTheLimitIsMarkedAsCapped() {
    #expect(FindMatchSummary(index: 7, total: 1000, limit: 1000).label == "7 of more than 1000")
    #expect(FindMatchSummary(index: 0, total: 1000, limit: 1000).label == "More than 1000 matches")
  }

  @Test(arguments: [(-1, 4), (9, 4), (2, -3), (Int.min, Int.max)])
  func inconsistentValuesFromTheEngineAreClamped(index: Int, total: Int) {
    let summary = FindMatchSummary(index: index, total: total, limit: 1000)
    #expect(summary.index >= 0)
    #expect(summary.total >= 0)
    #expect(summary.index <= summary.total)
  }
}

@Suite struct FindQueryTests {
  @Test func emptyOrMissingSelectionGivesNoPrefill() {
    #expect(FindQuery.prefill(fromSelection: nil) == nil)
    #expect(FindQuery.prefill(fromSelection: "") == nil)
    #expect(FindQuery.prefill(fromSelection: "\n  \n") == nil)
  }

  @Test func keepsOnlyTheFirstNonEmptyLine() {
    #expect(FindQuery.prefill(fromSelection: "\nerror: build\nsecond") == "error: build")
    #expect(FindQuery.prefill(fromSelection: "a\r\nb") == "a")
  }

  @Test func preservesInnerSpacesAndUnicode() {
    #expect(FindQuery.prefill(fromSelection: "  café 👩‍💻 ok  ") == "café 👩‍💻 ok")
  }

  @Test func capsLengthWithoutSplittingGraphemes() {
    let family = "👨‍👩‍👧‍👦"
    let long = String(repeating: family, count: FindQuery.maxPrefillCharacters + 10)
    let prefill = FindQuery.prefill(fromSelection: long)
    #expect(prefill?.count == FindQuery.maxPrefillCharacters)
    #expect(prefill?.allSatisfy { $0 == Character(family) } == true)
  }

  @Test func dropsControlCharacters() {
    #expect(FindQuery.prefill(fromSelection: "a\u{1b}[31mb\tc") == "a[31mb c")
  }
}
