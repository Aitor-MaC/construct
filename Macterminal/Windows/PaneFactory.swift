import Foundation

/// Why a pane is being created. The "Wake up" greeting only plays on root panes (app launch, new
/// window or new tab), never on splits.
enum PaneOrigin {
  case root
  case split
}

/// Builds a pane starting in the given directory; `nil` means the home directory.
typealias PaneFactory = @MainActor (URL?, PaneOrigin) -> TerminalPaneController
