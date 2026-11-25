import Foundation
import SwiftTerm

/// Cierre de un panel con la ventana abierta: como colgar un terminal. No depende de `deinit`
/// de `LocalProcess` (criterio de T1, I2): si en `escalationDelay` el shell sigue vivo, se mata
/// con su grupo y el grupo de primer plano del PTY.
public enum ShellHangup {
  public static let escalationDelay = Duration.milliseconds(500)

  @MainActor public static func hangUp(_ process: LocalProcess) {
    let shell = process.shellPid
    guard process.running, shell > 0 else { return }
    let foreground = tcgetpgrp(process.childfd)
    // zsh reenvía SIGHUP a sus trabajos; el kernel lo manda al grupo de primer plano cuando muere
    // el líder de la sesión.
    killpg(shell, SIGHUP)
    process.terminate()
    Task { @MainActor in
      do { try await Task.sleep(for: escalationDelay) } catch { return }
      guard process.running else { return }
      killpg(shell, SIGKILL)
      if foreground > 0, foreground != shell { killpg(foreground, SIGKILL) }
    }
  }
}
