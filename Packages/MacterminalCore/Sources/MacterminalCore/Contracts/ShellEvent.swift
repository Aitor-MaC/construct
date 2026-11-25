import Foundation

public enum ShellEvent: Sendable, Equatable {
  case promptStarted, inputStarted
  case commandStarted(command: String?, recordInHistory: Bool)
  case commandFinished(exitCode: Int32?)
  case directoryChanged(URL)
  case aiRequest(String)
}
