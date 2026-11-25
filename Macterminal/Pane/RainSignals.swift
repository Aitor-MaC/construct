import AppKit
import IOKit.ps
import MacterminalCore

/// Señales de toda la app que deciden si la lluvia corre (`RainPausePolicy`) y si el fondo puede
/// ser translúcido: app activa, modo de bajo consumo, Reduce Motion, Aumentar contraste y
/// corriente. Las de cada ventana (ocluida, clave, pantalla completa) las lee el panel. Un único
/// observador para todos los paneles; `onChange` los refresca.
@MainActor final class RainSignals {
  private(set) var appActive = NSApp?.isActive ?? false
  private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
  private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  private(set) var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
  private(set) var onPower = RainSignals.isOnExternalPower()

  var onChange: (() -> Void)?

  private var observers: [(NotificationCenter, NSObjectProtocol)] = []

  /// Notificaciones que cambian el estado de la lluvia de algún panel.
  private static let windowNotifications: [Notification.Name] = [
    NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
    NSWindow.didResignKeyNotification, NSWindow.didEnterFullScreenNotification,
    NSWindow.didExitFullScreenNotification,
  ]

  func start() {
    guard observers.isEmpty else { return }
    let app = NotificationCenter.default
    let workspace = NSWorkspace.shared.notificationCenter
    observe(app, NSApplication.didBecomeActiveNotification)
    observe(app, NSApplication.didResignActiveNotification)
    observe(app, Notification.Name.NSProcessInfoPowerStateDidChange)
    observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
    for name in Self.windowNotifications { observe(app, name) }
  }

  func stop() {
    for (center, token) in observers { center.removeObserver(token) }
    observers.removeAll()
  }

  private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
    let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      // Las notificaciones llegan a la cola principal (`queue: .main`).
      MainActor.assumeIsolated { self?.refresh() }
    }
    observers.append((center, token))
  }

  private func refresh() {
    appActive = NSApp.isActive
    lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    onPower = Self.isOnExternalPower()
    onChange?()
  }

  /// Corriente de la red (Inmersivo a pantalla completa sube a sus fps altos solo así).
  private static func isOnExternalPower() -> Bool {
    guard let source = IOPSGetProvidingPowerSourceType(nil)?.takeUnretainedValue() else {
      return false
    }
    return (source as String) == kIOPMACPowerKey
  }
}
