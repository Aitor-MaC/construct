import Foundation
import Observation

/// Dónde se guarda el flag. En la app es `UserDefaults`; los tests usan uno en memoria porque
/// cualquier dominio de UserDefaults, aunque se borre, deja un plist en ~/Library/Preferences.
public protocol FlagStore: AnyObject {
  func bool(forKey key: String) -> Bool
  func set(_ value: Bool, forKey key: String)
}

extension UserDefaults: FlagStore {}

/// Si el usuario ya ejecutó algún comando con la app (o cerró el estado vacío). Es estado
/// interno, no un ajuste, así que vive en UserDefaults como `onboardingCompleted`. Hay una sola
/// instancia en la app y cada panel la observa: al activarse, el estado vacío se va de todos.
@MainActor @Observable public final class FirstCommandFlag {
  public static let defaultsKey = "hasRunFirstCommand"

  public private(set) var isSet: Bool
  @ObservationIgnored private let store: FlagStore

  public init(defaults store: FlagStore) {
    self.store = store
    isSet = store.bool(forKey: Self.defaultsKey)
  }

  public func markSet() {
    guard !isSet else { return }
    isSet = true
    store.set(true, forKey: Self.defaultsKey)
  }
}
