import Testing

@testable import MacterminalCore

@Suite("FuzzyMatcher")
struct FuzzyMatcherTests {
  @Test("coincide en orden, sin distinguir mayúsculas ni diacríticos", arguments: [
    ("gco", "git checkout"),
    ("GCO", "git checkout"),
    ("cafe", "Café"),
    ("CAFÉ", "cafe"),
    ("nino", "El Niño"),
    ("日本", "日本語のコマンド"),
    ("ls", "ls"),
  ])
  func matches(query: String, text: String) {
    #expect(FuzzyMatcher.match(query, in: text) != nil)
  }

  @Test("no coincide si falta algún carácter o el orden es otro", arguments: [
    ("xyz", "git"),
    ("tig", "git"),
    ("gitt", "git"),
    ("a", ""),
  ])
  func doesNotMatch(query: String, text: String) {
    #expect(FuzzyMatcher.match(query, in: text) == nil)
  }

  @Test func emptyQueryMatchesEverythingWithZeroScore() {
    #expect(FuzzyMatcher.match("", in: "git") == FuzzyMatch(score: 0, ranges: []))
    #expect(FuzzyMatcher.match("", in: "") == FuzzyMatch(score: 0, ranges: []))
  }

  @Test func scoreOrderIsPrefixThenWordStartThenConsecutiveThenScattered() throws {
    let prefix = try #require(FuzzyMatcher.match("ab", in: "abz"))
    let wordStart = try #require(FuzzyMatcher.match("ab", in: "zz abz"))
    let consecutive = try #require(FuzzyMatcher.match("ab", in: "zabz"))
    let scattered = try #require(FuzzyMatcher.match("ab", in: "zazbz"))
    #expect(prefix.score > wordStart.score)
    #expect(wordStart.score > consecutive.score)
    #expect(consecutive.score > scattered.score)
  }

  @Test func prefixBeatsOtherAlignmentsEvenForLongQueries() throws {
    let query = String(repeating: "a", count: 40)
    let prefix = try #require(
      FuzzyMatcher.match(query, in: String(repeating: "a", count: 40) + "zzz"))
    let other = try #require(
      FuzzyMatcher.match(query, in: "b " + String(repeating: "a", count: 40)))
    #expect(prefix.score > other.score)
  }

  @Test func picksTheBestAlignmentNotTheFirstOne() throws {
    let text = "xab ab"
    let match = try #require(FuzzyMatcher.match("ab", in: text))
    // Gana la alineación con inicio de palabra (el segundo "ab").
    let start = try #require(match.ranges.first?.lowerBound)
    #expect(text.distance(from: text.startIndex, to: start) == 4)
  }

  @Test func rangesAreValidOnTheOriginalText() throws {
    let text = "El Niño 👨‍👩‍👧 Café"
    let match = try #require(FuzzyMatcher.match("nino cafe", in: text))
    for range in match.ranges {
      #expect(range.lowerBound >= text.startIndex && range.upperBound <= text.endIndex)
      #expect(!range.isEmpty)
    }
    for (a, b) in zip(match.ranges, match.ranges.dropFirst()) {
      #expect(a.upperBound <= b.lowerBound)
    }
    let covered = match.ranges.map { String(text[$0]) }.joined()
    #expect(covered.contains("Niño"))
    #expect(covered.contains("Café"))
  }

  @Test func consecutiveMatchesMergeIntoOneRange() throws {
    let text = "git checkout"
    let match = try #require(FuzzyMatcher.match("check", in: text))
    #expect(match.ranges.count == 1)
    #expect(String(text[match.ranges[0]]) == "check")
  }

  @Test func expandingFoldsStillMapToOriginalCharacters() throws {
    let text = "Straße"
    let match = try #require(FuzzyMatcher.match("strasse", in: text))
    #expect(String(text[match.ranges[0]]) == "Straße")
  }

  @Test func nonMatchingLongTextIsCheap() {
    let text = String(repeating: "a", count: 100_000)
    #expect(FuzzyMatcher.match("b", in: text) == nil)
  }
}
