import Foundation

public struct SessionID: Sendable, Hashable {
  public let value: UUID
  public init() { value = UUID() }
}
