import MacterminalCore
import SwiftUI

/// Primer arranque: pregunta el nombre del saludo "Wake up" sobre el panel de la primera
/// ventana. `void` al 92 % deja ver la lluvia detrás; "Hello." y "What’s your name?" se teclean al
/// ritmo del saludo con el cursor de fósforo, y el campo tiene el foco desde el principio para
/// poder escribir sin esperar. ⏎ continúa, esc lo deja para más tarde.
struct NameOnboardingView: View {
  /// Guarda el nombre ya saneado; `false` si no se pudo escribir el config (el overlay se queda).
  let onContinue: (String) -> Bool
  let onSkip: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var typed: [String] = []
  @State private var typing = true
  @State private var draft = ""
  @FocusState private var fieldFocused: Bool

  private static let lines = [String(localized: "Hello.", comment: "First line typed on the first-launch screen before asking the user's name."), String(localized: "What’s your name?", comment: "Second line typed on the first-launch screen asking the user's name.")]
  private static let glow = Intensity.inmersivo.profile
  private static let lineHeight: CGFloat = 22

  private var name: String? { GreetingName.sanitize(draft) }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      prompt
      VStack(alignment: .leading, spacing: 8) {
        field
        Text(String(localized: "Used in the “Wake up” greeting. You can change it in Settings.", comment: "Hint on the first-launch screen under the name field. “Wake up” is the name of the launch greeting animation."))
          .font(.system(size: 12))
          .foregroundStyle(BlockTokens.muted)
      }
      buttons
    }
    .padding(.horizontal, 16)
    .padding(.top, 18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(MatrixTheme.color(MatrixPalette.void, alpha: 0.92))
    // Los clics sobre el velo no llegan a la terminal de debajo.
    .contentShape(.rect)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(.isModal)
    .defaultFocus($fieldFocused, true)
    // esc llega como `cancelOperation:` desde el campo con foco; un `.cancelAction` en el botón
    // no lo recibe mientras escribe el field editor.
    .onExitCommand(perform: onSkip)
    .task {
      fieldFocused = true
      await typeLines()
    }
  }

  // MARK: Texto mecanografiado

  private var prompt: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(typed.enumerated()), id: \.offset) { index, line in
        HStack(spacing: 0) {
          Text(verbatim: line)
          if typing, index == typed.count - 1 { cursor }
        }
        .frame(height: Self.lineHeight)
      }
    }
    .font(.custom("MonaspaceKryptonNF-Medium", size: 15))
    .foregroundStyle(BlockTokens.accent)
    .shadow(
      color: MatrixTheme.color(MatrixPalette.ph400, alpha: Self.glow.accentGlowAlpha),
      radius: Self.glow.accentGlowRadius)
    // Se lee la frase entera, no letra a letra mientras se teclea.
    .frame(minHeight: Self.lineHeight * CGFloat(Self.lines.count), alignment: .topLeading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.lines.joined(separator: " "))
    .accessibilityAddTraits(.isHeader)
  }

  /// Bloque del cursor de la terminal: celda de 0,6 em, sin parpadeo mientras se teclea.
  private var cursor: some View {
    Rectangle()
      .fill(MatrixTheme.color(MatrixPalette.cursor))
      .frame(width: 9, height: 17)
      .padding(.leading, 1)
  }

  /// Mismo ritmo que "Wake up" (`WakeUpTimeline`): 62 ms por carácter y 520 ms entre líneas.
  /// Con Reduce Motion, el texto aparece completo.
  private func typeLines() async {
    guard !reduceMotion else {
      typed = Self.lines
      typing = false
      return
    }
    for (index, line) in Self.lines.enumerated() {
      if index > 0, !(await pause(WakeUpTimeline.linePause)) { return }
      typed.append("")
      for character in line {
        typed[index].append(character)
        if !(await pause(WakeUpTimeline.characterInterval)) { return }
      }
    }
    typing = false
  }

  /// `false` si se canceló (el overlay se cerró antes de acabar de teclear).
  private func pause(_ duration: Duration) async -> Bool {
    do {
      try await Task.sleep(for: duration)
      return true
    } catch {
      return false
    }
  }

  // MARK: Campo y botones

  private var field: some View {
    TextField(
      String(localized: "Your name", comment: "Placeholder of the name text field on the first-launch screen and in Settings."), text: $draft, prompt: Text(String(localized: "Your name", comment: "Placeholder of the name text field on the first-launch screen and in Settings."))
    )
    .textFieldStyle(.plain)
    .font(.custom("MonaspaceKryptonNF-Regular", size: 15))
    .foregroundStyle(BlockTokens.textBright)
    .tint(BlockTokens.accent)
    .focused($fieldFocused)
    .onSubmit(submit)
    .onChange(of: draft) { _, text in
      // El saludo no muestra más de 32 grafemas: el campo tampoco deja escribir más. Se sanea
      // antes de cortar para que un pegado con espacios o invisibles no pierda letras del final.
      if text.count > GreetingName.maxLength { draft = GreetingName.sanitize(text) ?? "" }
    }
    .padding(.horizontal, 10)
    .frame(width: 320, height: 32)
    .background(BlockTokens.background, in: .rect(cornerRadius: 4))
    .overlay {
      RoundedRectangle(cornerRadius: 4)
        .strokeBorder(
          fieldFocused ? BlockTokens.accent : BlockTokens.hairStrong,
          lineWidth: fieldFocused ? 1.5 : 1)
    }
    .accessibilityHint(String(localized: "Type how you want Construct to greet you.", comment: "VoiceOver hint of the name text field in Settings > Appearance."))
  }

  private var buttons: some View {
    HStack(spacing: 8) {
      Button(action: submit) {
        HStack(spacing: 8) {
          Text(String(localized: "Continue", comment: "Primary button of the first-launch screen that asks for the user's name. Verb."))
          keycap("⏎", tint: BlockTokens.background)
        }
      }
      .buttonStyle(BlockPrimaryButtonStyle())
      .keyboardShortcut(.defaultAction)
      .disabled(name == nil)
      .accessibilityHint(String(localized: "Saves the name and shows the greeting.", comment: "Accessibility hint of the Continue button on the first-launch screen."))
      Button(action: onSkip) {
        HStack(spacing: 8) {
          Text(String(localized: "Not Now", comment: "Secondary button of the first-launch screen: skips giving a name. Same meaning as “Later”."))
          keycap("esc", tint: BlockTokens.text)
        }
      }
      .buttonStyle(OnboardingSecondaryButtonStyle())
      .accessibilityHint(String(localized: "Uses your macOS account name and doesn’t ask again.", comment: "Accessibility hint of the Not Now button on the first-launch screen."))
    }
  }

  private func keycap(_ glyph: String, tint: Color) -> some View {
    Text(verbatim: glyph)
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(tint.opacity(0.14), in: .rect(cornerRadius: 4))
      .accessibilityHidden(true)
  }

  private func submit() {
    guard let name else { return }
    if !onContinue(name) { fieldFocused = true }
  }
}

/// "Not Now": la misma caja que la acción principal (28 pt, radio 6) en `surface2`, `surface3`
/// al pasar, borde `hairStrong`, anillo de foco `ph400` y escala 0,97 al pulsar.
private struct OnboardingSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    SecondaryButton(configuration: configuration)
  }

  private struct SecondaryButton: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
      configuration.label
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(BlockTokens.text)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(isHovered ? BlockTokens.surface3 : BlockTokens.surface2, in: .rect(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(BlockTokens.hairStrong, lineWidth: 0.5) }
        .overlay {
          if isFocused {
            RoundedRectangle(cornerRadius: 8).strokeBorder(BlockTokens.accent, lineWidth: 2).padding(-3)
          }
        }
        .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
        .animation(BlockTokens.press, value: configuration.isPressed)
        .animation(BlockTokens.hover, value: isHovered)
        .onHover { isHovered = $0 }
    }
  }
}

#Preview("First launch") {
  NameOnboardingView(onContinue: { _ in true }, onSkip: {})
    .frame(width: 720, height: 420)
    .background(BlockTokens.background)
}
