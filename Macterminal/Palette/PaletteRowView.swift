import MacterminalCore
import SwiftUI

/// One 32 pt row: title with highlighted matches and, on the right, shortcut, reason or date.
struct PaletteRowView: View {
  let match: PaletteMatch
  let availability: PaletteAvailability
  let isSelected: Bool
  let isCurrent: Bool

  private var item: PaletteItem { match.item }
  private var isEnabled: Bool { availability == .enabled }
  private var isMonospaced: Bool { item.group == .history || item.group == .folders }

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "checkmark")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(MatrixTheme.color(MatrixPalette.ph400))
        .frame(width: 14)
        .opacity(isCurrent ? 1 : 0)
      Text(highlightedTitle)
        .lineLimit(1)
        .truncationMode(isMonospaced ? .middle : .tail)
      Spacer(minLength: 12)
      trailing
    }
    .padding(.horizontal, 10)
    .frame(height: 32)
    .foregroundStyle(titleColor)
    .background {
      if isSelected {
        RoundedRectangle(cornerRadius: 6)
          .fill(MatrixTheme.color(MatrixPalette.ph400, alpha: 0.14))
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.title)
    .accessibilityValue(accessibilityValue)
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  @ViewBuilder private var trailing: some View {
    if case .disabled(let reason) = availability {
      // The reason is the information; `faint` on the title alone would not say why.
      Text(reason).font(.system(size: 12)).foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
    } else if let shortcut = item.shortcut {
      KeycapsView(glyphs: shortcut.glyphs)
    } else if isCurrent {
      Text("Current", comment: "Spoken suffix in the command palette for the setting value that is active now, read by VoiceOver.").font(.system(size: 12)).foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
    } else if let lastUsed = item.lastUsed {
      Text(lastUsed, format: .relative(presentation: .named))
        .font(.system(size: 12)).monospacedDigit()
        .foregroundStyle(MatrixTheme.color(MatrixPalette.muted))
    }
  }

  private var titleColor: Color {
    guard isEnabled else { return MatrixTheme.color(MatrixPalette.faint) }
    return MatrixTheme.color(isSelected ? MatrixPalette.fgBright : MatrixPalette.fg)
  }

  private var highlightedTitle: AttributedString {
    var title = AttributedString(item.title)
    title.font = isMonospaced ? .custom("MonaspaceKryptonNF-Regular", size: 12) : .system(size: 13)
    guard isEnabled else { return title }
    for range in match.ranges {
      guard let attributed = Range(range, in: title) else { continue }
      title[attributed].foregroundColor = MatrixTheme.color(MatrixPalette.ph400)
      title[attributed].font =
        isMonospaced
        ? .custom("MonaspaceKryptonNF-Medium", size: 12) : .system(size: 13, weight: .semibold)
    }
    return title
  }

  private var accessibilityValue: String {
    var parts: [String] = []
    if isCurrent { parts.append(String(localized: "Current", comment: "Spoken suffix in the command palette for the setting value that is active now, read by VoiceOver.")) }
    switch availability {
    case .disabled(let reason): parts.append(reason)
    case .enabled: if let shortcut = item.shortcut { parts.append(shortcut.spokenDescription) }
    }
    return parts.joined(separator: ", ")
  }
}

/// Keycaps in `surface2` with the floating hairline, as in the mock.
struct KeycapsView: View {
  let glyphs: [String]

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
        Text(glyph)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(MatrixTheme.color(MatrixPalette.fg))
          .frame(minWidth: 10)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(
            MatrixTheme.color(MatrixPalette.surface2), in: RoundedRectangle(cornerRadius: 4)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 4)
              .strokeBorder(
                MatrixTheme.color(MatrixPalette.hairStrong, alpha: MatrixPalette.hairStrongAlpha),
                lineWidth: 0.5)
          }
      }
    }
    .accessibilityHidden(true)
  }
}
