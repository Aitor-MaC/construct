import AppKit
import MacterminalCore
import SwiftUI

/// Graba un atajo de teclado con la tecla física (la misma tabla que registra `GlobalHotkey`).
/// Rechaza atajos sin ⌘, ⌃ ni ⌥, avisa si ya los usa una acción y esc cancela.
struct ShortcutRecorder: View {
  let label: String
  let shortcut: KeyShortcut?
  let onRecord: (KeyShortcut) -> Void

  @State private var isRecording = false
  @State private var monitor: Any?
  @State private var resignObserver: (any NSObjectProtocol)?
  @State private var problem: String?

  var body: some View {
    LabeledContent(label) {
      VStack(alignment: .trailing, spacing: 4) {
        Button(action: toggleRecording) {
          Text(isRecording ? String(localized: "Press the shortcut…", comment: "Prompt shown in the shortcut recorder while it waits for a key combination.") : currentText)
            .monospaced(!isRecording)
            .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .accessibilityLabel(label)
        .accessibilityValue(isRecording ? String(localized: "Recording", comment: "VoiceOver value of the shortcut recorder while it is waiting for a key combination.") : spokenText)
        .accessibilityHint(
          String(localized: "Click to record a new shortcut; esc cancels.", comment: "VoiceOver hint of the shortcut recorder button in Settings > Keyboard. esc is the Escape key."))
        if let problem {
          Label(problem, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
            .multilineTextAlignment(.trailing)
        } else if isRecording {
          Text(String(localized: "Use at least ⌘, ⌃ or ⌥. Esc cancels.", comment: "Hint shown under the shortcut recorder while recording. ⌘ ⌃ ⌥ are Command, Control and Option; Esc is Escape."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .onDisappear(perform: stopRecording)
  }

  private var currentText: String {
    shortcut.map(Self.symbols) ?? String(localized: "No shortcut", comment: "Value of a shortcut recorder that has no key combination assigned.")
  }

  private var spokenText: String {
    shortcut.map(Self.spoken) ?? String(localized: "No shortcut", comment: "Value of a shortcut recorder that has no key combination assigned.")
  }

  private func toggleRecording() {
    isRecording ? stopRecording() : startRecording()
  }

  private func startRecording() {
    guard let settingsWindow = NSApp.keyWindow else { return }
    problem = nil
    isRecording = true
    GlobalHotkey.isPaused = true
    // El monitor local ve la tecla antes que los menús: ⌘T no abre una pestaña al grabarlo. Solo
    // se queda con las teclas de Ajustes; las de las ventanas de terminal siguen su camino.
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      guard event.window === settingsWindow else { return event }
      handle(event)
      return nil
    }
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification, object: settingsWindow, queue: .main
    ) { _ in
      MainActor.assumeIsolated { stopRecording() }
    }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    monitor = nil
    resignObserver = nil
    if isRecording { GlobalHotkey.isPaused = false }
    isRecording = false
  }

  private func handle(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let modifiers = Self.modifiers(flags)
    let key = GlobalHotkey.keyCodes.first(where: { $0.value == Int(event.keyCode) })?.key
    if key == "escape", modifiers.isEmpty {
      stopRecording()
      return
    }
    guard let key,
      let recorded = KeyShortcut(
        configString: (modifiers.map(\.rawValue) + [key]).joined(separator: "+"))
    else {
      problem = String(localized: "That key can’t be used as a global shortcut.", comment: "Error in the shortcut recorder when the pressed key can't be registered system-wide.")
      return
    }
    switch SettingsInput.checkQuakeHotkey(recorded) {
    case .valid:
      problem = nil
      stopRecording()
      onRecord(recorded)
    case .missingModifier:
      problem = String(localized: "Add ⌘, ⌃ or ⌥: without them the shortcut would fire while you type.", comment: "Error under the shortcut recorder in Settings when the shortcut has no modifier key. ⌘ ⌃ ⌥ are the Command, Control and Option key symbols.")
    case .conflict(let action):
      problem = String(localized: "\(Self.symbols(recorded)) is already used by “\(action.title)”.", comment: "Error in the shortcut recorder: the first argument is the shortcut symbols, the second the name of the action that already uses it.")
    }
  }

  private static func modifiers(_ flags: NSEvent.ModifierFlags) -> [KeyShortcut.Modifier] {
    let pairs: [(NSEvent.ModifierFlags, KeyShortcut.Modifier)] = [
      (.control, .ctrl), (.option, .alt), (.shift, .shift), (.command, .cmd),
    ]
    return pairs.filter { flags.contains($0.0) }.map(\.1)
  }

  // MARK: - Presentación

  private static let modifierOrder: [(KeyShortcut.Modifier, symbol: String, name: String)] = [
    (.ctrl, "⌃", String(localized: "Control", comment: "Name of the Control (⌃) modifier key, read by VoiceOver in shortcut descriptions.")), (.alt, "⌥", String(localized: "Option", comment: "Name of the Option (⌥) modifier key, read by VoiceOver in shortcut descriptions.")),
    (.shift, "⇧", String(localized: "Shift", comment: "Name of the Shift (⇧) modifier key, read by VoiceOver in shortcut descriptions.")), (.cmd, "⌘", String(localized: "Command", comment: "Name of the Command (⌘) modifier key, read by VoiceOver in shortcut descriptions.")),
  ]

  static func symbols(_ shortcut: KeyShortcut) -> String {
    let mods = modifierOrder.filter { shortcut.modifiers.contains($0.0) }.map(\.symbol)
    return (mods + [keySymbol(shortcut.key)]).joined()
  }

  private static func spoken(_ shortcut: KeyShortcut) -> String {
    let mods = modifierOrder.filter { shortcut.modifiers.contains($0.0) }.map(\.name)
    return (mods + [keyName(shortcut.key)]).joined(separator: " + ")
  }

  private static func keySymbol(_ key: String) -> String {
    switch key {
    case "grave": "`"
    case "left": "←"
    case "right": "→"
    case "up": "↑"
    case "down": "↓"
    case "return": "↩"
    case "escape": "⎋"
    case "tab": "⇥"
    case "space": String(localized: "Space", comment: "Name of the Space bar key in a shortcut shown on screen (capitalized).")
    default: key.uppercased()
    }
  }

  private static func keyName(_ key: String) -> String {
    switch key {
    case "grave": String(localized: "grave accent", comment: "Spoken name of the backtick key (`), read by VoiceOver.")
    case "left": String(localized: "left arrow", comment: "Spoken name of the Left Arrow key, read by VoiceOver.")
    case "right": String(localized: "right arrow", comment: "Spoken name of the Right Arrow key, read by VoiceOver.")
    case "up": String(localized: "up arrow", comment: "Spoken name of the Up Arrow key, read by VoiceOver.")
    case "down": String(localized: "down arrow", comment: "Spoken name of the Down Arrow key, read by VoiceOver.")
    case "return": String(localized: "return", comment: "Spoken name of the Return key, read by VoiceOver.")
    case "escape": String(localized: "escape", comment: "Spoken name of the Escape key, read by VoiceOver.")
    case "tab": String(localized: "tab", comment: "Spoken name of the Tab key, read by VoiceOver (not a window tab).")
    case "space": String(localized: "space", comment: "Spoken name of the Space bar key, read by VoiceOver.")
    default: key.uppercased()
    }
  }
}
