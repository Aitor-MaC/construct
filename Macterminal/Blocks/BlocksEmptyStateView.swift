import SwiftUI

/// Primer uso (diseño §7): una frase bajo el prompt y un único botón. Desaparece de todos los
/// paneles con el primer comando o con ✕ (`EmptyStateVisibility`).
struct BlocksEmptyStateView: View {
  let directory: URL?
  let openPalette: () -> Void
  let dismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(headline) \(hint)", comment: "Two sentences joined with a space in the empty state of a terminal pane: the first is the session message, the second the usage hint.")
          .font(.system(size: 13))
          .lineSpacing(4)
          .frame(maxWidth: 440, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
        dismissButton
      }
      Button(action: openPalette) {
        HStack(spacing: 8) {
          Text(String(localized: "Open Palette", comment: "Label of the hint in the empty state that explains how to open the command palette."))
          Text(verbatim: "⇧⌘P")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(BlockTokens.background.opacity(0.14), in: .rect(cornerRadius: 4))
            .accessibilityLabel(String(localized: "Shift Command P", comment: "VoiceOver label of the Shift+Command+P shortcut hint; keep the key order."))
        }
      }
      .buttonStyle(BlockPrimaryButtonStyle())
    }
    .padding(.horizontal, 16)
    .padding(.top, 18)
  }

  private var dismissButton: some View {
    let label = String(localized: "Dismiss", comment: "Tooltip and VoiceOver label of the X button that hides the first-use hint of the terminal panes for good.")
    return Button(action: dismiss) {
      Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
    }
    .buttonStyle(BlockActionButtonStyle())
    .help(label)
    .accessibilityLabel(label)
  }

  private var headline: Text {
    Text(title).foregroundStyle(BlockTokens.textBright).fontWeight(.medium)
  }

  private var hint: Text {
    Text(String(localized: "Type a command, or open the palette to change the intensity, search your history or open a folder.", comment: "Hint of the empty state of a terminal pane."))
      .foregroundStyle(BlockTokens.muted)
  }

  private var title: String {
    guard let directory else { return String(localized: "New session.", comment: "Message of the empty state of a terminal pane when the folder is unknown.") }
    let path = (directory.path as NSString).abbreviatingWithTildeInPath
    return String(localized: "New session in \(path).", comment: "Message of the empty state of a terminal pane; the argument is the current folder path.")
  }
}
