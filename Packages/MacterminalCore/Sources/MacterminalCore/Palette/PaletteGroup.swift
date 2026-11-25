/// Secciones de la paleta, en el orden en que se muestran.
public enum PaletteGroup: Int, Sendable, CaseIterable, Comparable {
  case settings, actions, history, folders

  public var title: String {
    switch self {
    case .settings:
      String(localized: "Settings", bundle: .localized, comment: "Command palette section header.")
    case .actions:
      String(localized: "Actions", bundle: .localized, comment: "Command palette section header.")
    case .history:
      String(localized: "History", bundle: .localized, comment: "Command palette section header.")
    case .folders:
      String(localized: "Folders", bundle: .localized, comment: "Command palette section header.")
    }
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
