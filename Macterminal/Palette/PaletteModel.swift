import Foundation
import MacterminalCore
import MacterminalTerminal
import Observation

/// State of one open palette: query, filtered rows, selection and what ⏎ does.
@MainActor @Observable final class PaletteModel {
  var query = "" {
    didSet { if query != oldValue { refilter() } }
  }
  private(set) var sections: [PaletteSection] = []
  private var listing: PaletteListing
  var rowCount: Int { listing.matches.count }
  var selection: Int? { listing.selection }
  private(set) var isLoadingHistory = true
  let currentIntensity: Intensity?

  @ObservationIgnored private var items: [PaletteItem]
  @ObservationIgnored private var filterTask: Task<Void, Never>?
  @ObservationIgnored private let home: URL
  @ObservationIgnored private let canInsert: () -> Bool
  @ObservationIgnored private let canPerform: (TerminalAction) -> Bool
  @ObservationIgnored private let perform: (PaletteResult) -> InsertResult?
  @ObservationIgnored private let toasts: ToastCenter
  @ObservationIgnored private let onDismiss: () -> Void

  init(
    actions: [PaletteItem], currentIntensity: Intensity?,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    canInsert: @escaping () -> Bool, canPerform: @escaping (TerminalAction) -> Bool,
    perform: @escaping (PaletteResult) -> InsertResult?, toasts: ToastCenter,
    onDismiss: @escaping () -> Void
  ) {
    items = actions
    self.currentIntensity = currentIntensity
    self.home = home
    self.canInsert = canInsert
    self.canPerform = canPerform
    self.perform = perform
    self.toasts = toasts
    self.onDismiss = onDismiss
    // The action catalog is a few dozen rows: filtering it inline lets the palette open complete.
    listing = PaletteListing(
      query: "", matches: PaletteSearch.filter(actions, query: ""),
      isEnabled: { PaletteAvailability.of($0, canInsert: canInsert(), canPerform: canPerform) == .enabled })
    sections = PaletteSection.sections(of: listing.matches)
  }

  func applyHistory(commands: [HistoryEntry], directories: [URL]) {
    items = items.filter { $0.group == .settings || $0.group == .actions }
      + PaletteCatalog.historyItems(commands: commands, directories: directories, home: home)
    isLoadingHistory = false
    refilter()
  }

  func availability(of item: PaletteItem) -> PaletteAvailability {
    PaletteAvailability.of(item, canInsert: canInsert(), canPerform: canPerform)
  }

  func isCurrent(_ item: PaletteItem) -> Bool {
    guard let currentIntensity else { return false }
    return item.run == .action(.setIntensity(currentIntensity))
  }

  func moveSelection(by delta: Int) {
    listing.moveSelection(by: delta)
  }

  func select(_ index: Int) {
    listing.select(index)
  }

  /// ⏎ runs the row for what is typed now, even if its background filter has not published yet.
  func runSelection() {
    let current = listing.refreshed(for: query, items: items, isEnabled: isEnabled)
    if current.query != listing.query {
      filterTask?.cancel()
      publish(current)
    }
    guard let item = listing.selectedItem else { return }
    run(item)
  }

  func run(_ item: PaletteItem) {
    guard availability(of: item) == .enabled else { return }
    switch item.run {
    case .action:
      // Close first so the action finds the terminal, not the search field, as first responder.
      dismiss()
      _ = perform(item.run)
    case .insert:
      if let message = Self.rejectionMessage(for: perform(item.run)) {
        toasts.show(message)
      } else {
        dismiss()
      }
    }
  }

  func dismiss() {
    filterTask?.cancel()
    onDismiss()
  }

  /// `nil` when the text reached the prompt (or there was nothing to insert into).
  static func rejectionMessage(for result: InsertResult?) -> String? {
    switch result {
    case nil, .inserted?: nil
    case .notAtPrompt?:
      String(localized: "The prompt isn’t active. Wait for the command to finish and try again.", comment: "Error toast when inserting a command while another command is still running.")
    case .stale?: String(localized: "The prompt has changed. Choose it again.", comment: "Error toast when the command block action refers to a prompt that is gone.")
    case .unsafe(let rejection)?: rejection.errorDescription
    }
  }

  private func refilter() {
    filterTask?.cancel()
    let snapshot = items
    let query = query
    filterTask = Task {
      let filtered = await Self.filter(snapshot, query: query)
      // A newer keystroke or history load already replaced this request.
      guard !Task.isCancelled, query == self.query else { return }
      // Rows chosen with ↑↓ while history loaded stay chosen if they are still listed.
      let keptID = listing.query == query ? listing.selectedItem?.id : nil
      publish(PaletteListing(query: query, matches: filtered, keeping: keptID, isEnabled: isEnabled))
    }
  }

  /// Runs off the main actor so 2000 history rows never hold up a keystroke.
  @concurrent nonisolated private static func filter(_ items: [PaletteItem], query: String) async
    -> [PaletteMatch]
  {
    PaletteSearch.filter(items, query: query)
  }

  private func isEnabled(_ item: PaletteItem) -> Bool {
    availability(of: item) == .enabled
  }

  private func publish(_ newListing: PaletteListing) {
    listing = newListing
    sections = PaletteSection.sections(of: newListing.matches)
  }
}
