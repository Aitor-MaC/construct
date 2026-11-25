import AppKit
import SwiftUI

/// Puente entre el registro de acciones (AppKit) y la escena `Settings`: desde macOS 14 solo se
/// abre con el `OpenSettingsAction` del entorno de SwiftUI, y el selector `showSettingsWindow:`
/// ya no hace nada. Sin `@Observable` a propósito: lo rellena `AppCommands.body` y no debe
/// invalidar nada.
@MainActor final class SettingsOpener {
  var action: OpenSettingsAction?

  func open() {
    NSApp.activate()
    action?()
  }
}
