extension KeyShortcut {
  private struct ModifierLabel {
    let modifier: Modifier
    let glyph: String
    let spoken: String
  }

  /// Orden de modificadores de los menús de macOS: ⌃ ⌥ ⇧ ⌘.
  private static var modifierOrder: [ModifierLabel] { [
    ModifierLabel(
      modifier: .ctrl, glyph: "⌃",
      spoken: String(
        localized: "Control", bundle: .localized,
        comment: "Spoken name of the Control key, read by VoiceOver.")),
    ModifierLabel(
      modifier: .alt, glyph: "⌥",
      spoken: String(
        localized: "Option", bundle: .localized,
        comment: "Spoken name of the Option key, read by VoiceOver.")),
    ModifierLabel(
      modifier: .shift, glyph: "⇧",
      spoken: String(
        localized: "Shift", bundle: .localized,
        comment: "Spoken name of the Shift key, read by VoiceOver.")),
    ModifierLabel(
      modifier: .cmd, glyph: "⌘",
      spoken: String(
        localized: "Command", bundle: .localized,
        comment: "Spoken name of the Command key, read by VoiceOver.")),
  ] }

  private var activeModifiers: [ModifierLabel] {
    Self.modifierOrder.filter { modifiers.contains($0.modifier) }
  }

  /// Un keycap por modificador y otro para la tecla.
  public var glyphs: [String] { activeModifiers.map(\.glyph) + [keyGlyph] }

  /// Lo que lee VoiceOver: los símbolos ⇧⌘ no se pronuncian bien por sí solos.
  public var spokenDescription: String {
    (activeModifiers.map(\.spoken) + [spokenKey]).joined(separator: " ")
  }

  private var keyGlyph: String {
    switch key {
    case "left": "←"
    case "right": "→"
    case "up": "↑"
    case "down": "↓"
    case "grave": "`"
    case "return": "↩"
    case "escape": "⎋"
    case "tab": "⇥"
    case "space": "␣"
    case "plus": "+"
    default: key.uppercased()
    }
  }

  private var spokenKey: String {
    switch key {
    case "left":
      String(
        localized: "Left Arrow", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "right":
      String(
        localized: "Right Arrow", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "up":
      String(localized: "Up Arrow", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "down":
      String(
        localized: "Down Arrow", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "grave":
      String(
        localized: "Grave Accent", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "return":
      String(localized: "Return", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "escape":
      String(localized: "Escape", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "tab":
      String(localized: "Tab", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "space":
      String(localized: "Space", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case ",":
      String(localized: "Comma", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "plus":
      String(localized: "Plus", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    case "-":
      String(localized: "Minus", bundle: .localized, comment: "Spoken key name, read by VoiceOver.")
    default: key.uppercased()
    }
  }
}
