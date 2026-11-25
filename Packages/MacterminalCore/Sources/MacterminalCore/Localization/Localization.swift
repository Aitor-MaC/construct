import Foundation

/// Lets a test pin the language of every message the package resolves, so assertions on texts
/// don't depend on the language of the machine or of the `-testLanguage` the run uses. Outside
/// tests nothing sets it and the system language rules.
public enum Localization {
  @TaskLocal public static var language: String?

  /// A bundle with no translations, so the strings keep the English they are written in. The
  /// build only emits an `.lproj` for the languages the catalog translates, never for English.
  private static let untranslated = Bundle(path: "/var/empty")

  /// `base` itself when no language is pinned; otherwise the bundle that resolves that language.
  public static func bundle(_ base: Bundle) -> Bundle {
    guard let language else { return base }
    if let path = base.path(forResource: language, ofType: "lproj"), let pinned = Bundle(path: path) {
      return pinned
    }
    return untranslated ?? base
  }
}

extension Bundle {
  static var localized: Bundle { Localization.bundle(.module) }
}
