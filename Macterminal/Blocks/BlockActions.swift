import AppKit
import MacterminalCore
import MacterminalTerminal

/// Copiar, Copiar salida y Repetir de un bloque. Repetir escribe el comando en el prompt sin
/// ejecutarlo (sin `\r`) y solo con un token de inserción vigente (A8).
@MainActor struct BlockActions {
  let tracker: BlockTracker
  let resolve: (RowAnchor) -> Int?
  let textProvider: (Range<Int>) -> String
  let insertIntoPrompt: (String, InsertionToken) -> InsertResult
  let toasts: ToastCenter

  func command(of block: CommandBlock) -> String? {
    guard let command = block.command, !command.isEmpty else { return nil }
    return command
  }

  func canCopyOutput(_ block: CommandBlock) -> Bool {
    tracker.outputRows(of: block, resolve: resolve) != nil
  }

  func canRepeat(_ block: CommandBlock) -> Bool {
    command(of: block) != nil && tracker.insertionToken() != nil
  }

  func copyCommand(_ block: CommandBlock) {
    guard let command = command(of: block) else { return }
    copy(command)
    toasts.show(String(localized: "Copied", comment: "Label of the Copy button for one second after the command was copied, and toast text. Past participle."))
  }

  func copyOutput(_ block: CommandBlock) {
    guard let rows = tracker.outputRows(of: block, resolve: resolve) else { return }
    copy(textProvider(rows))
    toasts.show(String(localized: "Output copied", comment: "Toast shown after the output of a command block was copied to the clipboard."))
  }

  func repeatCommand(_ block: CommandBlock) {
    guard let command = command(of: block) else { return }
    let result = tracker.insertionToken().map { insertIntoPrompt(command, $0) } ?? .notAtPrompt
    if let message = Self.failureMessage(for: result) { toasts.show(message) }
  }

  private func copy(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
  }

  /// `nil` si se insertó: el resultado visible es el propio comando en el prompt.
  private static func failureMessage(for result: InsertResult) -> String? {
    switch result {
    case .inserted: nil
    case .notAtPrompt: String(localized: "Wait for the prompt to come back to repeat the command.", comment: "Error toast shown when the user clicks Repeat while another command is running.")
    case .stale: String(localized: "The prompt has changed. Click Repeat again.", comment: "Error toast shown when the user clicks Repeat on a block after the prompt changed; Repeat is the button name.")
    case .unsafe(let rejection):
      rejection.errorDescription ?? String(localized: "This command can’t be written to the prompt.", comment: "Error toast when a command contains characters that are not safe to type into the prompt.")
    }
  }
}
