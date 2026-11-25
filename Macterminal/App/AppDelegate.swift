import AppKit
import MacterminalCore
import OSLog

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Se crea con el delegado para que la escena `Settings` reciba el `ConfigStore` real.
  let workspace = Workspace()
  private var isTerminating = false
  private let signposter = OSSignposter(subsystem: "com.aitorgarcia.Macterminal", category: .pointsOfInterest)

  func applicationDidFinishLaunching(_ notification: Notification) {
    let launch = signposter.beginInterval("launch")
    do { try FontLoader.register() } catch { ToastCenter.shared.show(error.localizedDescription) }
    workspace.start()
    NSApp.activate()
    signposter.endInterval("launch", launch)
  }

  /// Responde tras guardar el historial (máx. 1 s); un fallo se registra y no impide salir.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminating else { return .terminateLater }
    isTerminating = true
    Task {
      await workspace.flushHistory()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  func applicationWillTerminate(_ notification: Notification) { workspace.terminateAllPanes() }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
