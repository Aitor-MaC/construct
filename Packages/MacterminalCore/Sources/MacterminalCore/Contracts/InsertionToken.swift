public struct InsertionToken: Sendable, Hashable {
  public let session: SessionID
  public let promptGeneration: UInt64
  public init(session: SessionID, promptGeneration: UInt64) {
    self.session = session
    self.promptGeneration = promptGeneration
  }
}
