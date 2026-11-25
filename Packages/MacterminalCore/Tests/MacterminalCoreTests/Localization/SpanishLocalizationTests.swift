import Foundation
import Testing

@testable import MacterminalCore

/// The interface is written in English; macOS picks Spanish from the catalog when it is the
/// preferred language. These tests read the compiled `es.lproj` so they don't depend on the
/// language of the machine running them.
@Suite struct SpanishLocalizationTests {
  private func spanish() throws -> Bundle {
    let path = try #require(Bundle.module.path(forResource: "es", ofType: "lproj"))
    return try #require(Bundle(path: path))
  }

  @Test(arguments: [
    ("Copy Block Command", "Copiar comando del bloque"),
    ("Settings…", "Ajustes…"),
    ("Available when the prompt is active", "Disponible con el prompt activo"),
    ("No matches", "Sin coincidencias"),
    ("must be subtle, balanced or immersive", "debe ser sutil, equilibrado o inmersivo"),
    ("Subtle Intensity", "Intensidad sutil"),
  ])
  func spanishTranslationExists(english: String, expected: String) throws {
    #expect(try spanish().localizedString(forKey: english, value: nil, table: nil) == expected)
  }

  @Test func reorderedPlaceholdersKeepTheirArguments() throws {
    let format = try spanish().localizedString(forKey: "%@ of more than %@", value: nil, table: nil)
    #expect(String(format: format, "7", "1000") == "7 de más de 1000")
  }

  @Test func durationsUseTheDecimalSeparatorOfTheRegion() {
    #expect(
      DurationFormat.short(.milliseconds(400), locale: Locale(identifier: "es_ES")) == "0,4 s")
    #expect(
      DurationFormat.short(.milliseconds(400), locale: Locale(identifier: "en_US")) == "0.4 s")
  }

  @Test(.language("es")) func resolvedMessagesFollowThePinnedLanguage() {
    #expect(FindMatchSummary(index: 0, total: 0, limit: 1000).label == "Sin coincidencias")
    #expect(FindMatchSummary(index: 3, total: 12, limit: 1000).label == "3 de 12")
    #expect(TerminalAction.copyBlockCommand.title == "Copiar comando del bloque")
    #expect(
      DurationFormat.spoken(.seconds(72), locale: Locale(identifier: "es_ES"))
        == "1 minuto 12 segundos")
  }

  @Test(.language("en")) func englishCanBePinnedWhateverTheRunLanguage() {
    #expect(FindMatchSummary(index: 0, total: 0, limit: 1000).label == "No matches")
  }
}
