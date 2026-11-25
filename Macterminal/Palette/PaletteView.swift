import MacterminalCore
import MacterminalTerminal
import SwiftUI

/// The ⇧⌘P HUD: 600 pt wide, 64 pt below the top of the terminal area. Never animated.
struct PaletteView: View {
  let model: PaletteModel
  /// Last pointer position seen over a row: hover selects only when the mouse really moved.
  @State private var lastPointer: CGPoint?

  private static let width: CGFloat = 600
  private static let topOffset: CGFloat = 64
  private static let rowHeight: CGFloat = 32
  private static let headerHeight: CGFloat = 28
  private static let listPadding: CGFloat = 6
  private static let maxListHeight: CGFloat = 320
  private static let skeletonRows = 3

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        // Clicking anywhere outside closes the palette, like Spotlight.
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { model.dismiss() }
          .accessibilityHidden(true)
        panel
          .frame(width: min(Self.width, proxy.size.width - 24))
          .padding(.top, Self.topOffset)
      }
    }
  }

  private var panel: some View {
    VStack(spacing: 0) {
      PaletteSearchField(model: model)
      hairline(alpha: MatrixPalette.hairStrongAlpha)
      results
      hairline(alpha: MatrixPalette.hairAlpha)
      footer
    }
    .background(PaletteBackground())
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          MatrixTheme.color(MatrixPalette.hairStrong, alpha: MatrixPalette.hairStrongAlpha),
          lineWidth: 0.5)
    }
    // 4.3: 0 4 16 black/40 %, 0 24 60 black/50 % (CSS blur = 2 × SwiftUI radius).
    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    .shadow(color: .black.opacity(0.5), radius: 30, y: 24)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(String(localized: "Command Palette", comment: "Title of the command palette window, read by VoiceOver."))
    .accessibilityAddTraits(.isModal)
  }

  @ViewBuilder private var results: some View {
    if model.rowCount == 0 && !model.isLoadingHistory {
      Text("Nothing matches. Try another word or press esc to go back.", comment: "Empty state of the command palette search; esc is the Escape key.")
        .font(.system(size: 13))
        .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
    } else {
      ScrollViewReader { scroller in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(model.sections) { section in
              header(section.group.title)
              ForEach(section.rows) { row in
                interactiveRow(row)
              }
            }
            if model.isLoadingHistory { PaletteSkeleton(rows: Self.skeletonRows) }
          }
          .padding(Self.listPadding)
        }
        .scrollIndicators(.automatic)
        .frame(height: listHeight)
        .onChange(of: model.selection) { _, selection in
          guard let selection, let id = rowID(at: selection) else { return }
          scroller.scrollTo(id)
        }
      }
    }
  }

  private func interactiveRow(_ row: PaletteRowEntry) -> some View {
    PaletteRowView(
      match: row.match, availability: model.availability(of: row.match.item),
      isSelected: model.selection == row.index, isCurrent: model.isCurrent(row.match.item)
    )
    .id(row.id)
    // Scrolling with ↓ moves rows under a still pointer; that must not steal the selection.
    .onContinuousHover(coordinateSpace: .global) { phase in
      guard case .active(let location) = phase, location != lastPointer else { return }
      let isFirstSighting = lastPointer == nil
      lastPointer = location
      if !isFirstSighting { model.select(row.index) }
    }
    .onTapGesture { model.run(row.match.item) }
    .accessibilityAction { model.run(row.match.item) }
  }

  private func header(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
      .padding(.horizontal, 10)
      .padding(.top, 10)
      .padding(.bottom, 4)
      .frame(height: Self.headerHeight, alignment: .bottomLeading)
      .accessibilityAddTraits(.isHeader)
  }

  private var footer: some View {
    HStack(spacing: 16) {
      Spacer()
      hint(["↑", "↓"], String(localized: "select", comment: "Keyboard hint at the bottom of the command palette next to the up/down arrow keys. Lowercase verb: “arrows to select”."))
      hint(["↩"], String(localized: "apply", comment: "Keyboard hint at the bottom of the command palette next to the Return key. Lowercase verb: “Return to apply”."))
      hint(["esc"], String(localized: "close", comment: "Keyboard hint at the bottom of the command palette next to the Esc key. Lowercase verb."))
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .accessibilityHidden(true)
  }

  private func hint(_ keys: [String], _ label: String) -> some View {
    HStack(spacing: 4) {
      KeycapsView(glyphs: keys)
      Text(label).font(.system(size: 11)).foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
    }
  }

  private func hairline(alpha: Double) -> some View {
    MatrixTheme.color(MatrixPalette.hair, alpha: alpha).frame(height: 0.5)
  }

  private var listHeight: CGFloat {
    var headers = model.sections.count
    var rows = model.rowCount
    if model.isLoadingHistory {
      headers += 1
      rows += Self.skeletonRows
    }
    let content = CGFloat(headers) * Self.headerHeight + CGFloat(rows) * Self.rowHeight
    return min(content + 2 * Self.listPadding, Self.maxListHeight)
  }

  private func rowID(at index: Int) -> String? {
    for section in model.sections {
      if let row = section.rows.first(where: { $0.index == index }) { return row.id }
    }
    return nil
  }
}

/// Search field with the focus on open and ↑↓ / ⏎ / esc handled here, never by the terminal.
private struct PaletteSearchField: View {
  @Bindable var model: PaletteModel
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14))
        .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
        .accessibilityHidden(true)
      TextField(
        String(localized: "Search commands", comment: "VoiceOver label of the command palette search field."), text: $model.query,
        prompt: Text("Search for an action, a setting or a previous command", comment: "Placeholder of the command palette search field.")
          .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
      )
      .textFieldStyle(.plain)
      .font(.system(size: 15))
      .foregroundStyle(MatrixTheme.color(MatrixPalette.fgBright))
      .tint(MatrixTheme.color(MatrixPalette.ph400))
      .autocorrectionDisabled()
      .focused($isFocused)
      .accessibilityLabel(String(localized: "Search commands", comment: "VoiceOver label of the command palette search field."))
      .onSubmit { model.runSelection() }
      .onKeyPress(.upArrow) {
        model.moveSelection(by: -1)
        return .handled
      }
      .onKeyPress(.downArrow) {
        model.moveSelection(by: 1)
        return .handled
      }
      .onKeyPress(.escape) {
        model.dismiss()
        return .handled
      }
      // The field editor may consume esc as cancelOperation before onKeyPress sees it.
      .onExitCommand { model.dismiss() }
    }
    .padding(.horizontal, 14)
    .frame(height: 46)
    .onAppear { isFocused = true }
  }
}

/// Loading rows for the history: `surface3` bars that breathe, still under Reduce Motion.
private struct PaletteSkeleton: View {
  let rows: Int
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isDimmed = false
  private static let widths: [CGFloat] = [0.62, 0.48, 0.55]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("History", comment: "Section header in the command palette for previously run commands, and label of the history loading state.")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(height: 28, alignment: .bottomLeading)
      ForEach(0..<rows, id: \.self) { row in
        GeometryReader { proxy in
          RoundedRectangle(cornerRadius: 4)
            .fill(MatrixTheme.color(MatrixPalette.surface3))
            .frame(width: proxy.size.width * Self.widths[row % Self.widths.count], height: 12)
            .frame(maxHeight: .infinity)
        }
        .padding(.leading, 34)
        .frame(height: 32)
      }
    }
    .opacity(isDimmed ? 0.55 : 1)
    .onAppear {
      guard !reduceMotion else { return }
      // Bounded by the history load: the view disappears as soon as the rows arrive.
      withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isDimmed = true }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "Loading history", comment: "VoiceOver label of the progress indicator in the command palette while history loads."))
  }
}

// MARK: - Previews

@MainActor private func previewModel(query: String = "", history: Bool = true) -> PaletteModel {
  let model = PaletteModel(
    actions: PaletteCatalog.actionItems(from: TerminalAction.catalog), currentIntensity: .equilibrado,
    home: URL(filePath: "/Users/neo"), canInsert: { true },
    canPerform: { $0 != .previousTab && $0 != .nextTab }, perform: { _ in .inserted },
    toasts: ToastCenter(), onDismiss: {})
  if history {
    let at = Date(timeIntervalSince1970: 1_763_640_000)
    model.applyHistory(
      commands: [
        HistoryEntry(command: "swift test --filter RainLayoutTests", lastUsed: at),
        HistoryEntry(command: "git commit -am \"Per-profile intensity\"", lastUsed: at),
      ],
      directories: [URL(filePath: "/Users/neo/Projects/zion")])
  }
  model.query = query
  return model
}

private func previewCanvas(_ model: PaletteModel) -> some View {
  PaletteView(model: model)
    .frame(width: 960, height: 560)
    .background(MatrixTheme.color(MatrixPalette.bg))
    .preferredColorScheme(.dark)
}

#Preview("With results") { previewCanvas(previewModel(query: "intens")) }
#Preview("No query") { previewCanvas(previewModel()) }
#Preview("No results") { previewCanvas(previewModel(query: "zzqx")) }
#Preview("Loading history") { previewCanvas(previewModel(history: false)) }
#Preview("Reduce transparency") {
  previewCanvas(previewModel(query: "git")).environment(\.paletteForcesOpaque, true)
}
