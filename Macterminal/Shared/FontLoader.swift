import AppKit
import CoreText

public enum FontLoader {
  public enum FontError: Error, LocalizedError {
    case missing(String)
    case registration(String)
    public var errorDescription: String? {
      switch self {
      case .missing(let name): String(localized: "The bundled font wasn’t found: \(name).", comment: "Toast shown at launch when a font file shipped inside the app is missing; the argument is the font file name.")
      case .registration(let name): String(localized: "The font couldn’t be registered: \(name).", comment: "Toast shown at launch when the system refuses to register a font shipped inside the app; the argument is the font file name.")
      }
    }
  }
  /// Fuente de `family` o, si no está disponible (registro fallido, familia no instalada), la
  /// monoespaciada del sistema: el texto de terminal nunca cae en una proporcional.
  public static func terminalFont(family: String, size: Double) -> NSFont {
    NSFont(name: family, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
  }

  public static func register(in bundle: Bundle = .main) throws {
    for style in ["Regular", "Medium", "Italic", "MediumItalic"] {
      let name = "MonaspaceKryptonNF-\(style)"
      guard
        let url = bundle.url(forResource: name, withExtension: "otf", subdirectory: "Fonts")
          ?? bundle.url(forResource: name, withExtension: "otf")
      else { throw FontError.missing(name) }
      var error: Unmanaged<CFError>?
      guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
        if let error { _ = error.takeRetainedValue() }
        throw FontError.registration(name)
      }
    }
  }
}
