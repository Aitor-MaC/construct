import MacterminalCore
import SwiftTerm
import SwiftUI

/// `TerminalView` real de SwiftTerm con la paleta de la app y salida con coincidencias, para
/// probar `MatrixFindBar` contra el motor de búsqueda de verdad.
private func findBarStage(query: String) -> NSView {
  let terminal = TerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 280))
  terminal.nativeBackgroundColor = MatrixTheme.nsColor(MatrixPalette.bg)
  terminal.nativeForegroundColor = MatrixTheme.nsColor(MatrixPalette.fg)
  terminal.selectedTextBackgroundColor = MatrixTheme.nsColor(MatrixPalette.selectionBg)
  terminal.feed(
    text: """
      $ swift build\r
      Compiling MacterminalCore FindMatchSummary.swift\r
      Compiling MacterminalCore SuggestionCardState.swift\r
      error: cannot find 'RainEngine' in scope\r
      Build complete with 1 error\r
      $ swift test --filter RainEngineTests\r
      ✔ Test run with 12 tests passed\r

      """)
  let bar = MatrixFindBar.install(on: terminal)
  bar.open()
  bar.updateQuery(query)
  return terminal
}

#Preview("Find · with matches") { findBarStage(query: "Compiling") }
#Preview("Find · no matches") { findBarStage(query: "zzz") }

private func cardStage(_ state: SuggestionCardState, panelWidth: CGFloat = 520) -> some View {
  SuggestionCardView(state: state, onInsert: { _ in }, onCancel: {})
    .padding(16)
    .frame(width: panelWidth)
    .padding(.vertical, 16)
    .background(MatrixTheme.color(MatrixPalette.bg))
}

private let sampleSuggestion = CommandSuggestion(
  command: "find . -name '*.swift' -mtime -1",
  explanation: "Lists the Swift files modified in the last 24 hours.")

#Preview("Card · loading") { cardStage(.loading) }
#Preview("Card · suggestion") { cardStage(.result(sampleSuggestion)) }
#Preview("Card · suggestion, 360 pt pane") {
  cardStage(.result(sampleSuggestion), panelWidth: 360)
}
#Preview("Card · loading, 360 pt pane") { cardStage(.loading, panelWidth: 360) }
#Preview("Card · not available") {
  cardStage(
    SuggestionCardState(
      error: .unavailable(
        reason: "Apple Intelligence is turned off. Turn it on in System Settings."))
      ?? .loading)
}
#Preview("Card · error") {
  cardStage(SuggestionCardState(error: .rateLimited) ?? .loading)
}

#Preview("Toast") {
  let center = ToastCenter()
  center.show(String(localized: "Output copied", comment: "Toast shown after the output of a command block was copied to the clipboard."))
  return ToastView(center: center)
    .frame(width: 520, height: 200)
    .background(MatrixTheme.color(MatrixPalette.bg))
}
