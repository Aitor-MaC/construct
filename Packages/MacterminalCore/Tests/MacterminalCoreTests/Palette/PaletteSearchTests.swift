import Foundation
import Testing

@testable import MacterminalCore

@Suite("PaletteSearch")
struct PaletteSearchTests {
  private let home = URL(filePath: "/Users/neo", directoryHint: .isDirectory)
  private let at = Date(timeIntervalSince1970: 1_700_000_000)

  private var catalog: [PaletteItem] { PaletteCatalog.actionItems(from: TerminalAction.catalog) }

  private func history(_ commands: [String], directories: [URL] = []) -> [PaletteItem] {
    PaletteCatalog.historyItems(
      commands: commands.map { HistoryEntry(command: $0, lastUsed: at) }, directories: directories,
      home: home)
  }

  @Test func emptyQueryKeepsEverythingInGroupOrder() {
    let items = history(["ls"], directories: [URL(filePath: "/tmp")]) + catalog
    let matches = PaletteSearch.filter(items, query: "  ")
    #expect(matches.count == items.count)
    #expect(matches.map(\.item.group) == matches.map(\.item.group).sorted())
    #expect(matches.allSatisfy { $0.ranges.isEmpty })
    #expect(
      matches.filter { $0.item.group == .actions }.map(\.item)
        == catalog.filter { $0.group == .actions })
  }

  @Test func intensQueryPutsIntensitySettingsFirst() {
    let matches = PaletteSearch.filter(catalog + history(["echo intensity"]), query: "intens")
    #expect(matches.first?.item.run == .action(.setIntensity(.sutil)))
    #expect(matches.prefix(3).allSatisfy { $0.item.group == .settings })
    #expect(matches.last?.item.group == .history)
  }

  @Test func withinAGroupBetterScoresComeFirstAndTiesKeepOrder() {
    let matches = PaletteSearch.filter(history(["xgitx", "git status", "git stash"]), query: "git")
    #expect(matches.map(\.item.title) == ["git status", "git stash", "xgitx"])
  }

  @Test func rangesPointAtTheMatchedCharactersOfTheTitle() throws {
    let matches = PaletteSearch.filter(history(["Café con leche"]), query: "cafe")
    let match = try #require(matches.first)
    #expect(match.ranges.map { String(match.item.title[$0]) } == ["Café"])
  }

  @Test func sectionsGroupContiguousRowsAndKeepFlatIndices() {
    let items = catalog + history(["git log"], directories: [URL(filePath: "/Users/neo/git")])
    let matches = PaletteSearch.filter(items, query: "g")
    let sections = PaletteSection.sections(of: matches)
    #expect(
      sections.map(\.group)
        == [.settings, .actions, .history, .folders].filter { group in
          matches.contains { $0.item.group == group }
        })
    #expect(sections.flatMap(\.rows).map(\.index) == Array(matches.indices))
    #expect(sections.flatMap(\.rows).map(\.id) == matches.map(\.id))
    #expect(PaletteSection.sections(of: []).isEmpty)
  }

  @Test func noMatchGivesEmptyResult() {
    #expect(PaletteSearch.filter(catalog, query: "zzqx").isEmpty)
  }

  #if DEBUG
    static let isOptimizedBuild = false
  #else
    static let isOptimizedBuild = true
  #endif

  /// El presupuesto de 50 ms es el de la app publicada; sin optimizar el plegado tarda unas 3 veces más.
  /// Se ejecuta con `swift test -c release`; en Debug el filtrado igualmente va fuera del hilo principal.
  @Test(.enabled(if: isOptimizedBuild))
  func twoThousandHistoryEntriesFilterWithinBudget() {
    let commands = (0..<2000).map {
      "git commit -m \"Cambio número \($0) en RainEngine\" --no-verify"
    }
    let items = catalog + history(commands)
    let clock = ContinuousClock()
    let elapsed = clock.measure { _ = PaletteSearch.filter(items, query: "gcne") }
    #expect(elapsed < .milliseconds(50), "\(elapsed)")
  }
}

@Suite("PaletteAvailability", .language("en"))
struct PaletteAvailabilityTests {
  private let insert = PaletteItem(group: .history, title: "ls", run: .insert("ls"))
  private let clear = PaletteItem(group: .actions, title: "Limpiar", run: .action(.clearScreen))

  @Test func insertionsNeedAnActivePrompt() {
    #expect(PaletteAvailability.of(insert, canInsert: true, canPerform: { _ in false }) == .enabled)
    #expect(
      PaletteAvailability.of(insert, canInsert: false, canPerform: { _ in true })
        == .disabled(reason: PaletteAvailability.promptRequiredReason))
    #expect(PaletteAvailability.promptRequiredReason == "Available when the prompt is active")
  }

  @Test func actionsFollowTheRegistry() {
    #expect(
      PaletteAvailability.of(clear, canInsert: false, canPerform: { $0 == .clearScreen })
        == .enabled)
    #expect(
      PaletteAvailability.of(clear, canInsert: true, canPerform: { _ in false })
        == .disabled(reason: PaletteAvailability.actionUnavailableReason))
  }
}

@Suite("PaletteSelection")
struct PaletteSelectionTests {
  @Test(
    "mueve y se queda en los extremos",
    arguments: [
      (0, 1, 3, 1), (2, 1, 3, 2), (0, -1, 3, 0), (1, -1, 3, 0), (5, 0, 3, 2),
    ])
  func clamps(current: Int, delta: Int, count: Int, expected: Int) {
    #expect(PaletteSelection.moved(current, by: delta, count: count) == expected)
  }

  @Test func noRowsMeansNoSelection() {
    #expect(PaletteSelection.moved(0, by: 1, count: 0) == nil)
  }
}
