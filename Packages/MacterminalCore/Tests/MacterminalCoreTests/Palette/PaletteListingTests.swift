import Foundation
import Testing

@testable import MacterminalCore

@Suite("PaletteListing")
struct PaletteListingTests {
  private let home = URL(filePath: "/Users/neo", directoryHint: .isDirectory)
  private let at = Date(timeIntervalSince1970: 1_700_000_000)

  private var items: [PaletteItem] {
    PaletteCatalog.historyItems(
      commands: [HistoryEntry(command: "ls -la", lastUsed: at)], directories: [], home: home)
      + PaletteCatalog.actionItems(from: TerminalAction.catalog)
  }

  private func listing(_ query: String, isEnabled: (PaletteItem) -> Bool = { _ in true })
    -> PaletteListing
  {
    PaletteListing(query: query, matches: PaletteSearch.filter(items, query: query), isEnabled: isEnabled)
  }

  @Test func startsOnTheFirstRowThatCanRun() {
    let listing = listing("") { $0.group != .history }
    #expect(listing.selectedItem?.group != .history)
    #expect(listing.selectedItem != nil)
  }

  @Test func withNothingEnabledStartsOnTheFirstRowAndEmptyHasNoSelection() {
    #expect(listing("") { _ in false }.selection == 0)
    #expect(listing("zzzzzzzz").selection == nil)
  }

  /// Teclear "ls" y ⏎ antes de que se publique el filtrado de "ls" no ejecuta la fila de "l".
  @Test func returnRunsTheRowOfTheTypedQueryEvenIfItsFilterWasNotPublished() {
    let published = listing("l")
    let current = published.refreshed(for: "ls -", items: items) { _ in true }
    let expected = PaletteSearch.filter(items, query: "ls -")
    #expect(current.query == "ls -")
    #expect(current.matches.map(\.id) == expected.map(\.id))
    #expect(current.selectedItem?.id == expected.first?.item.id)
    #expect(current.selectedItem?.id != published.selectedItem?.id)
    #expect(published.refreshed(for: "l", items: items) { _ in true }.selection == published.selection)
  }

  /// Al llegar el historial se conserva la fila elegida con ↑↓ si sigue en la lista.
  @Test func keepsTheChosenRowWhenTheListIsRebuilt() throws {
    var listing = listing("")
    listing.moveSelection(by: 3)
    let chosen = try #require(listing.selectedItem)
    let rebuilt = PaletteListing(
      query: "", matches: PaletteSearch.filter(items, query: ""), keeping: chosen.id) { _ in true }
    #expect(rebuilt.selectedItem == chosen)
    let gone = PaletteListing(
      query: "", matches: PaletteSearch.filter(items, query: ""), keeping: "nada") { _ in true }
    #expect(gone.selection == 0)
  }

  @Test func selectionStopsAtTheEdges() {
    var listing = listing("")
    listing.moveSelection(by: -5)
    #expect(listing.selection == 0)
    listing.moveSelection(by: 10_000)
    #expect(listing.selection == listing.matches.count - 1)
    let outOfRange = listing.select(listing.matches.count)
    #expect(!outOfRange)
    let inRange = listing.select(1)
    #expect(inRange)
    #expect(listing.selection == 1)
  }
}
