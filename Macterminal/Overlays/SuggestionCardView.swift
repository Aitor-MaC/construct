import MacterminalCore
import SwiftUI

/// Tarjeta de la sugerencia de la IA de un panel. Muestra el comando tal cual y nunca lo ejecuta:
/// "Insert" (⏎) entrega la sugerencia al llamador, que la escribe en el prompt sin retorno.
/// "Cancel" (esc) la descarta. El panel la crea y la destruye con él.
/// Mide hasta 440 pt y se estrecha con el panel; el margen con el borde lo pone el llamador.
struct SuggestionCardView: View {
  private enum Action { case insert, cancel }

  let state: SuggestionCardState
  let onInsert: (CommandSuggestion) -> Void
  let onCancel: () -> Void

  /// El foco vive en cada botón y no en la tarjeta: así el anillo solo sale en el que lo tiene.
  /// "Insert" es la acción por defecto en cuanto hay sugerencia.
  @FocusState private var focus: Action?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Suggestion", comment: "Title of the AI suggestion card that proposes a shell command. Noun.")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
        .accessibilityHidden(true)
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityDescription)
      actions
    }
    .padding(14)
    .frame(maxWidth: 440)
    .background(OverlayStyle.surface, in: .rect(cornerRadius: 8))
    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(OverlayStyle.border, lineWidth: 0.5) }
    .floatingShadow()
    .environment(\.colorScheme, .dark)
    .animation(reduceMotion ? nil : OverlayStyle.enterExit, value: state)
    .focusEffectDisabled()
    .onAppear { focus = defaultAction }
    .onChange(of: state) { focus = defaultAction }
    .onKeyPress(.return) {
      guard let suggestion = state.insertable else { return .ignored }
      onInsert(suggestion)
      return .handled
    }
    .onExitCommand(perform: onCancel)
    .accessibilityElement(children: .contain)
  }

  private var defaultAction: Action { state.insertable == nil ? .cancel : .insert }

  @ViewBuilder private var content: some View {
    switch state {
    case .loading:
      SuggestionSkeleton()
    case .result(let suggestion):
      VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: ControlPictures.visible(suggestion.command))
          .font(OverlayStyle.commandFont)
          .foregroundStyle(MatrixTheme.color(MatrixPalette.fgBright))
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
        if let explanation = suggestion.explanation, !explanation.isEmpty {
          Text(verbatim: explanation)
            .font(.system(size: 12))
            .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .transition(.opacity)
    case .unavailable(let reason):
      notice(reason, symbol: "info.circle", tint: MatrixPalette.muted)
    case .failed(let message):
      notice(message, symbol: "exclamationmark.triangle", tint: MatrixPalette.errTint)
    }
  }

  private func notice(_ text: String, symbol: String, tint: RGB) -> some View {
    Label {
      Text(verbatim: text)
        .foregroundStyle(MatrixTheme.color(MatrixPalette.fg))
        .fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: symbol).foregroundStyle(MatrixTheme.color(tint))
    }
    .font(.system(size: 12))
    .transition(.opacity)
  }

  private var actions: some View {
    HStack(spacing: 8) {
      Spacer()
      Button(action: onCancel) {
        HStack(spacing: 6) {
          Text(state == .loading ? String(localized: "Cancel", comment: "Button in the AI suggestion card that cancels the request while it is loading.") : String(localized: "Close", comment: "Button that closes the AI suggestion card. Verb."))
          Keycap(symbol: "esc")
        }
      }
      .buttonStyle(OverlayButtonStyle(kind: .secondary))
      .focusable()
      .focused($focus, equals: .cancel)
      if let suggestion = state.insertable {
        Button { onInsert(suggestion) } label: {
          HStack(spacing: 6) {
            Text("Insert", comment: "Button of the AI suggestion card that writes the suggested command into the prompt without running it. Verb.")
            Keycap(symbol: "⏎", onAccent: true)
          }
        }
        .buttonStyle(OverlayButtonStyle(kind: .primary))
        .focusable()
        .focused($focus, equals: .insert)
        .help(String(localized: "Writes the command to the prompt without running it", comment: "Tooltip of the Repeat button on a command block."))
      }
    }
  }
}

/// Esqueleto estático del estado "cargando": sin brillo en bucle (prohibido) ni spinner. Cada
/// barra llega a su ancho tope y se acorta con la tarjeta en paneles estrechos.
private struct SuggestionSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      bar(maxWidth: 260, height: 14)
      bar(maxWidth: 380, height: 10)
      bar(maxWidth: 220, height: 10)
    }
    .padding(.vertical, 2)
  }

  private func bar(maxWidth: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 4)
      .fill(MatrixTheme.color(MatrixPalette.surface3))
      .frame(maxWidth: maxWidth, minHeight: height, maxHeight: height)
  }
}
