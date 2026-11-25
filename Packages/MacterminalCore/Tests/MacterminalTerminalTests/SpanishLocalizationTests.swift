import Foundation
import Testing

@testable import MacterminalTerminal

/// Reads the compiled `es.lproj` of the module so the result doesn't depend on the language of
/// the machine running the tests.
@Suite struct SpanishLocalizationTests {
  @Test func shellErrorsHaveTheirSpanishTranslation() throws {
    let path = try #require(Bundle.module.path(forResource: "es", ofType: "lproj"))
    let spanish = try #require(Bundle(path: path))
    let format = spanish.localizedString(
      forKey: "The shell exited at launch (code %@)", value: nil, table: nil)
    #expect(String(format: format, "1") == "El shell terminó al arrancar (código 1)")
    #expect(
      spanish.localizedString(forKey: "The AI took too long", value: nil, table: nil)
        == "La IA tardó demasiado")
  }

  @Test(.language("es")) func pinnedLanguageResolvesShellMessagesInSpanish() {
    #expect(StartupFailurePolicy.message(exitCode: 1) == "El shell terminó al arrancar (código 1)")
  }
}
