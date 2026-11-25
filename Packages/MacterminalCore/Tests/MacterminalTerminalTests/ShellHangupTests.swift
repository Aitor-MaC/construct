import Foundation
import MacterminalCore
import SwiftTerm
import Testing

@testable import MacterminalTerminal

/// Recoge la salida de un `LocalProcess` real y avisa cuando aparece un patrón.
private final class ProcessProbe: LocalProcessDelegate {
  private(set) var output = ""
  private var waiters: [(Regex<AnyRegexOutput>, CheckedContinuation<Void, Never>)] = []

  func processTerminated(_ source: LocalProcess, exitCode: Int32?) {}
  func getWindowSize() -> winsize { winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0) }

  func dataReceived(slice: ArraySlice<UInt8>) {
    output += String(decoding: slice, as: UTF8.self)
    waiters.removeAll { pattern, continuation in
      guard output.contains(pattern) else { return false }
      continuation.resume()
      return true
    }
  }

  @MainActor func waitFor(_ pattern: Regex<AnyRegexOutput>) async {
    guard !output.contains(pattern) else { return }
    await withCheckedContinuation { waiters.append((pattern, $0)) }
  }
}

/// Espera la salida de un proceso que no es hijo nuestro con `NOTE_EXIT` de kqueue.
@MainActor private func waitForExit(_ pid: pid_t) async {
  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
    let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
    var resumed = false
    let finish = {
      guard !resumed else { return }
      resumed = true
      source.cancel()
      continuation.resume()
    }
    source.setEventHandler(handler: finish)
    source.resume()
    // Si ya había salido antes de registrar la fuente, kqueue no avisa.
    if kill(pid, 0) != 0 && errno == ESRCH { finish() }
  }
}

@MainActor @Suite struct ShellHangupTests {
  @Test(.timeLimit(.minutes(1)))
  func hangUpLeavesNoShellChildrenWithinOneSecond() async throws {
    let probe = ProcessProbe()
    let process = LocalProcess(delegate: probe, dispatchQueue: .main)
    process.startProcess(
      executable: "/bin/zsh", args: ["-f", "-i"],
      environment: ["TERM=xterm-256color", "PATH=/usr/bin:/bin"], execName: "-zsh")
    process.send(data: ArraySlice("sleep 600 & echo bg=$!\nsh -c 'echo fg=$$; exec sleep 601'\n".utf8))
    let pids = try Regex(#"bg=(\d+)[\s\S]*fg=(\d+)"#)
    await probe.waitFor(pids)
    let match = try #require(probe.output.firstMatch(of: pids))
    let background = try #require(match.output[1].substring.flatMap { pid_t($0) })
    let foreground = try #require(match.output[2].substring.flatMap { pid_t($0) })
    let shell = process.shellPid

    let start = ContinuousClock.now
    ShellHangup.hangUp(process)
    for pid in [shell, foreground, background] { await waitForExit(pid) }
    #expect(ContinuousClock.now - start <= .seconds(1))
  }

  /// Lo que hace `TerminalPaneController.terminate()` con la ventana abierta: el shell de login
  /// con la integración de zsh, arrancado con el mismo `ShellLaunchPlan` que el panel. El
  /// `LocalProcess` sigue vivo durante toda la prueba, así que no interviene ningún `deinit`.
  @Test(.timeLimit(.minutes(1)))
  func terminatingAnIntegratedLoginShellLeavesNoChildrenWithinOneSecond() async throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "hangup-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: base) }
    let zdotdir = try ZshIntegration.install(in: base)
    let plan = try ShellLaunchPlan.make(
      shell: "/bin/zsh", inherited: ["HOME": base.path, "PATH": "/usr/bin:/bin"],
      locale: Locale(identifier: "es_ES"),
      integration: ShellLaunchPlan.Integration(
        zdotdir: zdotdir, options: PromptOptions(prompt: false, autosuggest: false),
        nonce: SessionNonce.random()))
    let probe = ProcessProbe()
    let process = LocalProcess(delegate: probe, dispatchQueue: .main)
    process.startProcess(
      executable: plan.executable, args: [], environment: plan.environmentList,
      execName: plan.execName, currentDirectory: base.path)
    process.send(data: ArraySlice("sleep 600 & echo bg=$!\nsh -c 'echo fg=$$; exec sleep 601'\n".utf8))
    let pids = try Regex(#"bg=(\d+)[\s\S]*fg=(\d+)"#)
    await probe.waitFor(pids)
    let match = try #require(probe.output.firstMatch(of: pids))
    let background = try #require(match.output[1].substring.flatMap { pid_t($0) })
    let foreground = try #require(match.output[2].substring.flatMap { pid_t($0) })
    let shell = process.shellPid

    let start = ContinuousClock.now
    ShellHangup.hangUp(process)
    for pid in [shell, foreground, background] { await waitForExit(pid) }
    #expect(ContinuousClock.now - start <= .seconds(1))
    withExtendedLifetime(process) {}
  }
}
