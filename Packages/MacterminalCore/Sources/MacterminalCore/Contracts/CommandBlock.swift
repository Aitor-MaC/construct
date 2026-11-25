import Foundation

public struct CommandBlock: Sendable, Identifiable {
  public enum State: Sendable { case editing, running, finished }
  public let id: UUID
  public var command: String?
  public var cwd: URL?
  public var promptAnchor: RowAnchor
  public var outputAnchor: RowAnchor?
  public var endAnchor: RowAnchor?
  public var startedAt: Date?
  public var startedInstant: ContinuousClock.Instant?
  public var duration: Duration?
  public var exitCode: Int32?
  public var state: State
  public var recordInHistory: Bool
  public init(
    id: UUID = UUID(), command: String? = nil, cwd: URL? = nil, promptAnchor: RowAnchor,
    outputAnchor: RowAnchor? = nil, endAnchor: RowAnchor? = nil, startedAt: Date? = nil,
    startedInstant: ContinuousClock.Instant? = nil, duration: Duration? = nil,
    exitCode: Int32? = nil, state: State = .editing, recordInHistory: Bool = true
  ) {
    self.id = id
    self.command = command
    self.cwd = cwd
    self.promptAnchor = promptAnchor
    self.outputAnchor = outputAnchor
    self.endAnchor = endAnchor
    self.startedAt = startedAt
    self.startedInstant = startedInstant
    self.duration = duration
    self.exitCode = exitCode
    self.state = state
    self.recordInHistory = recordInHistory
  }
}
