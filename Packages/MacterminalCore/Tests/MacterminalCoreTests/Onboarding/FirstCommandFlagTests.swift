import Foundation
import Testing

@testable import MacterminalCore

/// Almacén en memoria: un dominio de UserDefaults, aunque se borre con
/// `removePersistentDomain`, deja un plist vacío en ~/Library/Preferences que cfprefsd vuelve a
/// escribir.
private final class InMemoryFlagStore: FlagStore {
  private var values: [String: Bool] = [:]
  func bool(forKey key: String) -> Bool { values[key] ?? false }
  func set(_ value: Bool, forKey key: String) { values[key] = value }
}

@MainActor @Suite struct FirstCommandFlagTests {
  @Test func startsUnsetOnAFreshInstall() {
    #expect(!FirstCommandFlag(defaults: InMemoryFlagStore()).isSet)
  }

  @Test func markingItShowsAtOnceOnTheSameInstance() {
    let flag = FirstCommandFlag(defaults: InMemoryFlagStore())
    flag.markSet()
    #expect(flag.isSet)
  }

  @Test func markingItPersistsAcrossLaunches() {
    let store = InMemoryFlagStore()
    FirstCommandFlag(defaults: store).markSet()

    #expect(FirstCommandFlag(defaults: store).isSet)
    #expect(store.bool(forKey: FirstCommandFlag.defaultsKey))
  }
}
