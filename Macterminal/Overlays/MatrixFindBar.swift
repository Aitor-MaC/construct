import AppKit
import MacterminalCore
import SwiftTerm
import SwiftUI

/// Barra de búsqueda ⌘F de un panel, montada sobre la `TerminalView` con su API pública de
/// búsqueda (`findNext`, `findPrevious`, `searchMatchSummary`). SwiftTerm 1.99.3 no expone un
/// proveedor de barra ni el resaltado de todas las coincidencias: su barra propia
/// (`TerminalFindBarView`) es privada y solo aparece con `performFindPanelAction`, que la app no
/// envía. La coincidencia actual se marca con la selección de SwiftTerm.
@Observable final class MatrixFindBar {
  /// Tope de coincidencias que cuenta SwiftTerm en cada actualización del contador.
  static let summaryLimit = 1000

  private(set) var isVisible = false
  private(set) var query = ""
  /// `nil` mientras el campo está vacío: no hay búsqueda, así que no hay contador.
  private(set) var summary: FindMatchSummary?
  /// Cambia cada vez que la barra pide el foco para su campo.
  private(set) var focusRequest = 0

  @ObservationIgnored private weak var terminal: TerminalView?
  @ObservationIgnored private weak var host: NSView?

  private init(terminal: TerminalView) {
    self.terminal = terminal
  }

  /// Crea la barra del panel y la coloca, oculta, en la esquina superior derecha de `terminal`.
  static func install(on terminal: TerminalView) -> MatrixFindBar {
    let bar = MatrixFindBar(terminal: terminal)
    let host = NSHostingView(rootView: FindBarView(bar: bar))
    host.translatesAutoresizingMaskIntoConstraints = false
    host.isHidden = true
    terminal.addSubview(host)
    NSLayoutConstraint.activate([
      host.topAnchor.constraint(equalTo: terminal.topAnchor, constant: 8),
      host.trailingAnchor.constraint(equalTo: terminal.trailingAnchor, constant: -16),
      host.leadingAnchor.constraint(greaterThanOrEqualTo: terminal.leadingAnchor, constant: 16),
    ])
    bar.host = host
    return bar
  }

  /// ⌘F: muestra la barra con la primera línea de la selección, si la hay, y enfoca el campo.
  func open() {
    setVisible(true)
    if let prefill = FindQuery.prefill(fromSelection: terminal?.getSelection()) {
      updateQuery(prefill)
    }
    focusRequest &+= 1
  }

  /// esc: oculta la barra y devuelve el foco a la terminal; la coincidencia queda seleccionada.
  func close() {
    setVisible(false)
    guard let terminal else { return }
    terminal.window?.makeFirstResponder(terminal)
  }

  func updateQuery(_ text: String) {
    // Con el mismo texto, `findNext` buscaría desde la selección actual y saltaría a la siguiente
    // coincidencia: reabrir ⌘F o un `Binding` que reescribe el valor no deben mover la búsqueda.
    guard text != query else {
      if !text.isEmpty { refreshSummary() }
      return
    }
    query = text
    guard let terminal, !text.isEmpty else {
      terminal?.clearSearch()
      publish(nil)
      return
    }
    terminal.findNext(text)
    refreshSummary()
  }

  /// ⏎
  func findNext() {
    guard let terminal, !query.isEmpty else { return }
    terminal.findNext(query)
    refreshSummary()
  }

  /// ⇧⏎
  func findPrevious() {
    guard let terminal, !query.isEmpty else { return }
    terminal.findPrevious(query)
    refreshSummary()
  }

  private func refreshSummary() {
    guard let terminal else { return }
    let counts = terminal.searchMatchSummary(query, limit: Self.summaryLimit)
    publish(FindMatchSummary(index: counts.index, total: counts.total, limit: Self.summaryLimit))
  }

  private func publish(_ newSummary: FindMatchSummary?) {
    let changed = newSummary?.label != summary?.label
    summary = newSummary
    guard changed, isVisible, let label = newSummary?.label else { return }
    AccessibilityNotification.Announcement(label).post()
  }

  private func setVisible(_ visible: Bool) {
    isVisible = visible
    host?.isHidden = !visible
  }
}

/// Contenido de la barra: material propio (`surface2`, borde `hairStrong`, radio 6), sin
/// translucidez sobre el lienzo. Aparece y desaparece sin animación: es una acción de teclado.
struct FindBarView: View {
  let bar: MatrixFindBar
  @FocusState private var fieldFocused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12))
        .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
        .accessibilityHidden(true)
      field
      counter
      HStack(spacing: 2) {
        Button(action: bar.findPrevious) { Image(systemName: "chevron.up") }
          .help(String(localized: "Previous (⇧⏎)", comment: "Tooltip of the button that goes to the previous find match; ⇧⏎ is Shift+Return."))
          .accessibilityLabel(String(localized: "Previous match", comment: "VoiceOver label of the button that goes to the previous find match."))
        Button(action: bar.findNext) { Image(systemName: "chevron.down") }
          .help(String(localized: "Next (⏎)", comment: "Tooltip of the button that goes to the next find match; ⏎ is the Return key."))
          .accessibilityLabel(String(localized: "Next match", comment: "VoiceOver label of the button that goes to the next find match."))
      }
      .disabled(bar.summary?.hasMatches != true)
      Button(action: bar.close) { Image(systemName: "xmark") }
        .help(String(localized: "Close (esc)", comment: "Tooltip and label of the close button of the command palette; esc is the Escape key."))
        .accessibilityLabel(String(localized: "Close search", comment: "VoiceOver label of the button that closes the find bar in the terminal."))
    }
    .buttonStyle(OverlayButtonStyle(kind: .icon))
    .font(.system(size: 11, weight: .semibold))
    .padding(.leading, 10)
    .padding(.trailing, 5)
    .frame(height: 32)
    .background(OverlayStyle.surface, in: .rect(cornerRadius: 6))
    .overlay {
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(fieldFocused ? OverlayStyle.focusRing : OverlayStyle.border,
                      lineWidth: fieldFocused ? 2 : 1)
    }
    .floatingShadow()
    .environment(\.colorScheme, .dark)
    .onChange(of: bar.focusRequest, initial: true) { fieldFocused = bar.isVisible }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(String(localized: "Find in terminal", comment: "VoiceOver label of the find bar container in the terminal window."))
  }

  private var field: some View {
    TextField(
      String(localized: "Find", comment: "Placeholder of the find bar text field in the terminal. Verb."),
      text: Binding(get: { bar.query }, set: { bar.updateQuery($0) })
    )
    .textFieldStyle(.plain)
    .font(.system(size: 13))
    .foregroundStyle(MatrixTheme.color(MatrixPalette.fgBright))
    .frame(minWidth: 140, idealWidth: 200)
    .focused($fieldFocused)
    .focusEffectDisabled()
    .onSubmit(bar.findNext)
    .onKeyPress(.return, phases: .down) { press in
      guard press.modifiers.contains(.shift) else { return .ignored }
      bar.findPrevious()
      return .handled
    }
    .onExitCommand(perform: bar.close)
    .accessibilityLabel(String(localized: "Text to find", comment: "VoiceOver label of the find bar text field."))
  }

  @ViewBuilder private var counter: some View {
    if let summary = bar.summary {
      Text(summary.label)
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(
          MatrixTheme.color(summary.hasMatches ? MatrixPalette.muted : MatrixPalette.errTint)
        )
        .lineLimit(1)
        .fixedSize()
    }
  }
}
