import Carbon.HIToolbox
import MacterminalCore
import OSLog

enum GlobalHotkeyError: Error, LocalizedError, Equatable {
  case unsupportedKey(String)
  case missingModifier
  case alreadyInUse
  case registrationFailed(OSStatus)

  var errorDescription: String? {
    switch self {
    case .unsupportedKey(let key):
      String(localized: "The Quake shortcut uses a key that can’t be registered: \(key). Choose another one.", comment: "Warning about the Quake shortcut; the argument is the key name from the config file.")
    case .missingModifier:
      String(localized: "The Quake shortcut needs cmd, ctrl, alt or shift so it doesn’t steal keystrokes.", comment: "Warning about the config file value of the Quake shortcut. cmd, ctrl, alt and shift are literal words typed in the config file; do not translate them.")
    case .alreadyInUse:
      String(localized: "Another app already uses that Quake shortcut. Choose another combination.", comment: "Error in Settings when the global shortcut that shows the Quake terminal is taken by another app.")
    case .registrationFailed:
      String(localized: "The Quake shortcut couldn’t be registered. Try another combination.", comment: "Toast shown when the system refuses the global shortcut for the Quake terminal.")
    }
  }
}

/// System-wide shortcut through Carbon `RegisterEventHotKey`, which needs no Accessibility
/// permission, unlike a global `NSEvent` monitor.
final class GlobalHotkey {
  private static let signature: OSType = 0x4D54_514B  // "MTQK"
  private static var nextID: UInt32 = 1
  private static let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "hotkey")

  private(set) var shortcut: KeyShortcut
  private let hotKeyID: EventHotKeyID
  private let handler: () -> Void
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?

  private static let live = NSHashTable<GlobalHotkey>.weakObjects()

  /// While Settings records a shortcut, Carbon would swallow the current combination before the
  /// recorder sees it: every hotkey is unregistered and comes back when recording ends.
  static var isPaused = false {
    didSet {
      guard isPaused != oldValue else { return }
      for hotkey in live.allObjects { isPaused ? hotkey.unregister() : hotkey.reregister() }
    }
  }

  init(shortcut: KeyShortcut, handler: @escaping () -> Void) throws(GlobalHotkeyError) {
    self.shortcut = shortcut
    self.handler = handler
    hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.nextID)
    Self.nextID += 1
    try installEventHandler()
    if !Self.isPaused { hotKeyRef = try Self.register(shortcut, id: hotKeyID) }
    Self.live.add(self)
  }

  isolated deinit {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
  }

  /// Re-registers with a new combination; if it fails, the previous one stays active.
  func update(to newShortcut: KeyShortcut) throws(GlobalHotkeyError) {
    guard newShortcut != shortcut else { return }
    guard !Self.isPaused else {
      shortcut = newShortcut
      return
    }
    let previous = hotKeyRef
    if let previous { UnregisterEventHotKey(previous) }
    hotKeyRef = nil
    do {
      hotKeyRef = try Self.register(newShortcut, id: hotKeyID)
      shortcut = newShortcut
    } catch {
      do {
        hotKeyRef = try Self.register(shortcut, id: hotKeyID)
      } catch {
        // The user still sees the original error; the lost fallback is only logged.
        Self.logger.error("Couldn't restore the previous Quake shortcut")
      }
      throw error
    }
  }

  private func unregister() {
    if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
    hotKeyRef = nil
  }

  private func reregister() {
    do {
      hotKeyRef = try Self.register(shortcut, id: hotKeyID)
    } catch {
      ToastCenter.shared.show(error.localizedDescription)
    }
  }

  fileprivate func handle(_ pressedID: EventHotKeyID) -> OSStatus {
    guard pressedID.signature == hotKeyID.signature, pressedID.id == hotKeyID.id else {
      return OSStatus(eventNotHandledErr)
    }
    handler()
    return noErr
  }

  private func installEventHandler() throws(GlobalHotkeyError) {
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    // Unretained: the handler is removed in deinit, before self goes away.
    let status = InstallEventHandler(
      GetApplicationEventTarget(), hotKeyEventCallback, 1, &eventType,
      Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)
    guard status == noErr else {
      Self.logger.error("InstallEventHandler failed: \(status, privacy: .public)")
      throw .registrationFailed(status)
    }
  }

  private static func register(_ shortcut: KeyShortcut, id: EventHotKeyID) throws(GlobalHotkeyError)
    -> EventHotKeyRef?
  {
    guard let keyCode = keyCodes[shortcut.key] else { throw .unsupportedKey(shortcut.key) }
    let modifiers = carbonModifiers(shortcut.modifiers)
    guard modifiers != 0 else { throw .missingModifier }
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      UInt32(keyCode), modifiers, id, GetApplicationEventTarget(), 0, &ref)
    logger.info("Quake shortcut registration; OSStatus: \(status, privacy: .public)")
    switch status {
    case noErr: return ref
    case OSStatus(eventHotKeyExistsErr): throw .alreadyInUse
    default: throw .registrationFailed(status)
    }
  }

  private static func carbonModifiers(_ modifiers: Set<KeyShortcut.Modifier>) -> UInt32 {
    var result: UInt32 = 0
    if modifiers.contains(.cmd) { result |= UInt32(cmdKey) }
    if modifiers.contains(.ctrl) { result |= UInt32(controlKey) }
    if modifiers.contains(.alt) { result |= UInt32(optionKey) }
    if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
    return result
  }

  /// Physical ANSI key positions for the names `KeyShortcut(configString:)` accepts.
  /// Also read by the Settings shortcut recorder, so both agree on the physical key.
  static let keyCodes: [String: Int] = [
    "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
    "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
    "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
    "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
    "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
    "z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket,
    "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
    ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash,
    "grave": kVK_ANSI_Grave, "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow,
    "down": kVK_DownArrow, "return": kVK_Return, "escape": kVK_Escape, "tab": kVK_Tab,
    "space": kVK_Space,
  ]
}

/// Carbon delivers application-target events on the main thread.
private nonisolated let hotKeyEventCallback: EventHandlerUPP = { _, event, userData in
  guard let event, let userData else { return OSStatus(eventNotHandledErr) }
  var pressedID = EventHotKeyID()
  let status = GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
  guard status == noErr else { return status }
  // The address crosses into the main actor as a plain integer; the object is used only there.
  let address = UInt(bitPattern: userData)
  return MainActor.assumeIsolated {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else {
      return OSStatus(eventNotHandledErr)
    }
    return Unmanaged<GlobalHotkey>.fromOpaque(pointer).takeUnretainedValue().handle(pressedID)
  }
}
