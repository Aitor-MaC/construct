public struct KeyShortcut: Sendable, Hashable {
  public enum Modifier: String, Sendable, Hashable { case cmd, ctrl, alt, shift }
  public let key: String
  public let modifiers: Set<Modifier>
  public init?(configString: String) {
    let pieces = configString.lowercased().split(separator: "+", omittingEmptySubsequences: false)
      .map(String.init)
    guard let key = pieces.last,
      key.count == 1
        // "+" separa las piezas, así que la tecla + se escribe "plus".
        || ["grave", "left", "right", "up", "down", "return", "escape", "tab", "space", "plus"]
          .contains(key)
    else { return nil }
    var modifiers = Set<Modifier>()
    for piece in pieces.dropLast() {
      guard let modifier = Modifier(rawValue: piece), modifiers.insert(modifier).inserted else {
        return nil
      }
    }
    self.key = key
    self.modifiers = modifiers
  }
}
