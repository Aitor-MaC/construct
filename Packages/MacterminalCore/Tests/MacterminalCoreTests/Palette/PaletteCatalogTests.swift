import Foundation
import Testing

@testable import MacterminalCore

/// Historial real: las entradas salen de `HistoryStore`, el productor que usa la app.
private final class PaletteHistoryFixture: @unchecked Sendable {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("macterminal-palette-\(UUID().uuidString)", isDirectory: true)
  let store: HistoryStore
  private static let t0 = Date(timeIntervalSince1970: 1_700_000_000)

  init(limit: Int = 2000) {
    store = HistoryStore(fileURL: directory.appendingPathComponent("history.json"), limit: limit)
  }

  func record(_ commands: [String], directories: [URL] = []) async {
    for (offset, command) in commands.enumerated() {
      await store.record(command: command, cwd: nil, at: Self.t0.addingTimeInterval(Double(offset)))
    }
    for (offset, url) in directories.enumerated() {
      await store.recordDirectory(url, at: Self.t0.addingTimeInterval(Double(offset)))
    }
  }

  deinit { try? FileManager.default.removeItem(at: directory) }
}

@Suite("PaletteCatalog")
struct PaletteCatalogTests {
  private let home = URL(filePath: "/Users/neo", directoryHint: .isDirectory)

  @Test func intensitiesAreSettingsAndTheRestAreActions() {
    let items = PaletteCatalog.actionItems(from: TerminalAction.catalog)
    let settings = items.filter { $0.group == .settings }.map(\.run)
    #expect(settings == Intensity.allCases.map { .action(.setIntensity($0)) })
    #expect(items.filter { $0.group == .actions }.contains { $0.run == .action(.clearScreen) })
    #expect(items.filter { $0.group == .actions }.first?.shortcut == TerminalAction.newWindow.shortcut)
  }

  @Test func paletteDoesNotOfferToOpenItself() {
    let items = PaletteCatalog.actionItems(from: TerminalAction.catalog)
    #expect(!items.contains { $0.run == .action(.commandPalette) })
  }

  @Test func historyInsertsTheCommandWithoutReturn() async {
    let fixture = PaletteHistoryFixture()
    await fixture.record(["ls -la", "git status"])
    let commands = await fixture.store.recentCommands(limit: 10)
    let items = PaletteCatalog.historyItems(commands: commands, directories: [], home: home)
    #expect(items.map(\.title) == ["git status", "ls -la"])
    #expect(items.map(\.run) == [.insert("git status"), .insert("ls -la")])
    #expect(items.allSatisfy { $0.group == .history && $0.lastUsed != nil })
  }

  @Test func foldersInsertQuotedChangeDirectoryAndShowAbbreviatedPath() async {
    let fixture = PaletteHistoryFixture()
    let project = URL(filePath: "/Users/neo/It's here")
    await fixture.record([], directories: [URL(filePath: "/tmp"), project])
    let directories = await fixture.store.recentDirectories(limit: 10)
    let items = PaletteCatalog.historyItems(commands: [], directories: directories, home: home)
    #expect(items.map(\.title) == ["~/It's here", "/tmp"])
    #expect(items.map(\.run) == [.insert("cd '/Users/neo/It'\\''s here'"), .insert("cd '/tmp'")])
    #expect(items.allSatisfy { $0.group == .folders })
  }

  @Test("abrevia la carpeta personal", arguments: [
    ("/Users/neo", "~"),
    ("/Users/neo/", "~"),
    ("/Users/neo/Proyectos", "~/Proyectos"),
    ("/Users/neon", "/Users/neon"),
    ("/var/log", "/var/log"),
  ])
  func abbreviatesHome(path: String, expected: String) {
    #expect(PaletteCatalog.displayPath(of: URL(filePath: path), home: home) == expected)
  }

  @Test func identifiersAreUniqueAcrossGroups() async {
    let fixture = PaletteHistoryFixture()
    await fixture.record(["cd '/tmp'", "ls"], directories: [URL(filePath: "/tmp")])
    let items =
      PaletteCatalog.actionItems(from: TerminalAction.catalog)
      + PaletteCatalog.historyItems(
        commands: await fixture.store.recentCommands(limit: 10),
        directories: await fixture.store.recentDirectories(limit: 10), home: home)
    #expect(Set(items.map(\.id)).count == items.count)
  }
}
