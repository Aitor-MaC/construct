import Foundation

public struct PaneID: Sendable, Hashable {
  private let rawValue = UUID()
  public init() {}
}
