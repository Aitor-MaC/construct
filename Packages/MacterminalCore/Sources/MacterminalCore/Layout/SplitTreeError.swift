import Foundation

public enum SplitTreeError: Error, LocalizedError, Equatable {
  case paneNotFound, duplicatePane

  public var errorDescription: String? {
    switch self {
    case .paneNotFound:
      String(
        localized: "The pane no longer exists.", bundle: .localized,
        comment: "Error for a split action on a closed pane.")
    case .duplicatePane:
      String(
        localized: "That pane is already in the window.", bundle: .localized,
        comment: "Error for a split action with a duplicated pane.")
    }
  }
}
