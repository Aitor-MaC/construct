import AppKit
import MacterminalCore
import Observation

@MainActor public struct ActionContext {
  public var focusedPane: TerminalPaneController?
  public var window: NSWindow?
  public init(focusedPane: TerminalPaneController? = nil, window: NSWindow? = nil) {
    self.focusedPane = focusedPane
    self.window = window
  }
}

@MainActor @Observable public final class ActionRegistry {
  public static let shared = ActionRegistry()
  public var context = ActionContext()
  private struct Registration {
    let isEnabled: (ActionContext) -> Bool
    let handler: (ActionContext) -> Void
  }
  private var registrations: [TerminalAction: Registration] = [:]
  public init() {}
  public func register(
    _ action: TerminalAction, isEnabled: @escaping (ActionContext) -> Bool = { _ in true },
    handler: @escaping (ActionContext) -> Void
  ) {
    registrations[action] = Registration(isEnabled: isEnabled, handler: handler)
  }
  public func canPerform(_ action: TerminalAction, in context: ActionContext) -> Bool {
    registrations[action]?.isEnabled(context) ?? false
  }
  public func perform(_ action: TerminalAction) {
    guard let registration = registrations[action], registration.isEnabled(context) else { return }
    registration.handler(context)
  }
}
