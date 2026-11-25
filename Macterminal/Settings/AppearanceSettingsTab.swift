import MacterminalCore
import SwiftUI

/// Apariencia: intensidad con vista previa en vivo, fuente, tamaño y opacidad del fondo.
struct AppearanceSettingsTab: View {
  let config: TerminalConfig
  let save: ConfigSave

  private static let bundledFont = TerminalConfig.defaults.fontFamily
  /// `NSFont(name:)` no lo encuentra y el terminal cae en la monoespaciada del sistema.
  private static let systemFont = "SF Mono"
  /// Escribir en el config tras una pausa al teclear, no en cada letra.
  private static let nameDebounce = Duration.milliseconds(600)

  @State private var nameField = EditableConfigField(value: nil, normalize: GreetingName.sanitize)
  @FocusState private var nameFocused: Bool

  var body: some View {
    Form {
      Section(String(localized: "Matrix Rain", comment: "Section title in Settings > Appearance for the falling-characters background effect. “Matrix” refers to the film.")) {
        Picker(String(localized: "Intensity", comment: "Picker label in Settings > Appearance for the Matrix rain intensity."), selection: intensity) {
          ForEach(Intensity.allCases, id: \.self) { level in
            Text(level.settingsTitle).tag(level)
          }
        }
        .pickerStyle(.segmented)
        IntensityPreviewView(
          intensity: config.intensity, fontFamily: config.fontFamily, fontSize: config.fontSize
        )
        .frame(height: 128)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          String(localized: "Preview of the \(config.intensity.settingsTitle) intensity", comment: "VoiceOver label of the rain preview in the Settings picker; the argument is the intensity name (Subtle, Balanced, Immersive)."))
        Text(config.intensity.settingsSummary)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Section(String(localized: "Text", comment: "Section title in Settings > Appearance for font options. Noun.")) {
        Picker(String(localized: "Font", comment: "Picker label in Settings > Appearance for the terminal font family."), selection: fontFamily) {
          Text(verbatim: Self.bundledFont).tag(Self.bundledFont)
          Text(String(localized: "SF Mono (system)", comment: "Name of the system monospaced font option in the font picker. SF Mono is Apple's font name; keep it.")).tag(Self.systemFont)
          if ![Self.bundledFont, Self.systemFont].contains(config.fontFamily) {
            Text(String(localized: "\(config.fontFamily) (from file)", comment: "Font picker option for a font family set in the configuration file that isn't in the list; the argument is the family name.")).tag(config.fontFamily)
          }
        }
        LabeledContent(String(localized: "Size", comment: "Label of the font size control in Settings > Appearance. Noun.")) {
          HStack(spacing: 6) {
            Text(String(localized: "\(fontSize.wrappedValue) pt", comment: "Visible font size in Settings > Appearance. pt is the abbreviation of points."))
              .monospacedDigit()
              .accessibilityHidden(true)
            Stepper(String(localized: "Size", comment: "Label of the font size control in Settings > Appearance. Noun."), value: fontSize, in: 10...24)
              .labelsHidden()
              .accessibilityValue(String(localized: "\(fontSize.wrappedValue) points", comment: "VoiceOver value of the font size stepper in Settings > Appearance; spoken in full, not abbreviated."))
          }
        }
        LabeledContent(String(localized: "Background opacity", comment: "Slider label in Settings > Appearance for how opaque the terminal window background is.")) {
          Slider(value: backgroundOpacity, in: 0.5...1, step: 0.05) {
            Text(String(localized: "Background opacity", comment: "Slider label in Settings > Appearance for how opaque the terminal window background is."))
          } minimumValueLabel: {
            Text(0.5, format: .percent)
          } maximumValueLabel: {
            Text(1.0, format: .percent)
          }
          .labelsHidden()
          .accessibilityValue(Text(config.backgroundOpacity, format: .percent))
        }
      }
      greetingSection
    }
    .formStyle(.grouped)
    .frame(width: SettingsLayout.width, height: 590)
    .onAppear { nameField.sync(external: config.greetingName) }
    .task {
      // AppKit da el foco al primer campo al hacer key la ventana, después de `onAppear`; Ajustes
      // abre sin foco en el nombre para que nada se confirme sin que el usuario lo toque.
      await Task.yield()
      nameFocused = false
    }
    .onChange(of: config.greetingName) { _, name in nameField.sync(external: name) }
  }

  // MARK: - Saludo

  private var greetingSection: some View {
    Section {
      TextField(String(localized: "Your name", comment: "Placeholder of the name text field on the first-launch screen and in Settings."), text: nameDraft, prompt: systemNamePrompt)
        .focused($nameFocused)
        .onSubmit(commitName)
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .task(id: nameField.draft) {
          do { try await Task.sleep(for: Self.nameDebounce) } catch { return }
          commitName()
        }
    } header: {
      Text(String(localized: "Greeting", comment: "Section title in Settings > Appearance for the personalized “Wake up” greeting shown at launch."))
    } footer: {
      Text(String(localized: "Used in the “Wake up” greeting. Leave empty to use your macOS account name.", comment: "Hint under the name field in Settings. “Wake up” is the name of the launch greeting animation, a Matrix film reference."))
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  /// Vacío, el campo enseña el nombre que se usará en su lugar.
  private var systemNamePrompt: Text? {
    WakeUpGreetingView.currentGivenName().flatMap(GreetingName.sanitize).map { Text(verbatim: $0) }
  }

  private var nameDraft: Binding<String> {
    Binding(get: { nameField.draft }, set: { nameField.edit($0) })
  }

  /// Solo si el usuario editó: guarda el nombre saneado o, vacío, borra `greeting-name` y
  /// vuelve al de macOS.
  private func commitName() {
    switch nameField.commit(saved: config.greetingName) {
    case .set(let name): save(.greetingName, name)
    case .remove: save.remove(.greetingName)
    case nil: break
    }
  }

  private var intensity: Binding<Intensity> {
    Binding(get: { config.intensity }, set: { save(.intensity, $0.rawValue) })
  }

  private var fontFamily: Binding<String> {
    Binding(get: { config.fontFamily }, set: { save(.fontFamily, $0) })
  }

  /// `font-size` en pt enteros (10-24); un valor decimal del archivo se muestra redondeado.
  private var fontSize: Binding<Int> {
    Binding(get: { Int(config.fontSize.rounded()) }, set: { save(.fontSize, String($0)) })
  }

  /// `background-opacity` es una fracción 0,5-1; el paso de 0,05 limita las escrituras al arrastrar.
  private var backgroundOpacity: Binding<Double> {
    Binding(
      get: { config.backgroundOpacity },
      set: { save(.backgroundOpacity, String(format: "%.2f", $0)) })
  }
}

extension Intensity {
  var settingsTitle: String {
    switch self {
    case .sutil: String(localized: "Subtle", comment: "Name of the weakest Matrix rain intensity level. Used as a picker option.")
    case .equilibrado: String(localized: "Balanced", comment: "Name of the middle Matrix rain intensity level (between Subtle and Immersive). Used as a picker option.")
    case .inmersivo: String(localized: "Immersive", comment: "Name of the strongest Matrix rain intensity level. Used as a picker option.")
    }
  }

  fileprivate var settingsSummary: String {
    switch self {
    case .sutil: String(localized: "Faint rain, no glow. For long working sessions.", comment: "Description of the Subtle rain intensity in the Settings picker.")
    case .equilibrado: String(localized: "Visible rain and a slight glow on the accent.", comment: "Description of the Balanced rain intensity in the Settings picker.")
    case .inmersivo:
      String(localized: "Dense rain, glowing text and scan lines.", comment: "Description of the Immersive rain intensity in the Settings picker.")
    }
  }
}
