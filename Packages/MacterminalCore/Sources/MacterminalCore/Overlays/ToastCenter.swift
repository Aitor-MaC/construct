import Observation

/// Un aviso concreto. `id` distingue dos llamadas a `show` con el mismo texto, para que la vista
/// reinicie el tiempo en pantalla y VoiceOver vuelva a anunciarlo.
public struct Toast: Equatable, Sendable {
  public let id: Int
  public let text: String
}

@MainActor @Observable public final class ToastCenter {
  public static let shared = ToastCenter()
  public private(set) var current: Toast?
  @ObservationIgnored private var lastID = 0
  public init() {}

  public func show(_ text: String) {
    lastID &+= 1
    current = Toast(id: lastID, text: text)
  }

  /// Retira `toast` solo si sigue en pantalla: si otro lo ha sustituido, no se toca.
  public func dismiss(_ toast: Toast) {
    guard current == toast else { return }
    current = nil
  }
}
