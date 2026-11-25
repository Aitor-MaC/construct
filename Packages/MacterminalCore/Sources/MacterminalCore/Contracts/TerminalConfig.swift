import Foundation

public struct TerminalConfig: Sendable, Equatable {
  public var fontFamily = "Monaspace Krypton NF"
  public var fontSize: Double = 13
  public var intensity: Intensity = .equilibrado
  public var prompt = true
  public var autosuggest = true
  public var promptUserHost = PromptUserHost.always
  public var promptPath = PromptPath.full
  public var backgroundOpacity: Double = 1 {
    didSet {
      backgroundOpacity = backgroundOpacity.isFinite ? min(1, max(0.5, backgroundOpacity)) : 1
    }
  }
  public var quakeHotkey = KeyShortcut(configString: "ctrl+grave")
  public var shell: String
  /// Nombre del saludo, ya saneado con `GreetingName.sanitize`; `nil` = sin configurar.
  public var greetingName: String?
  public init(shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh") {
    self.shell = shell
  }
  public static var defaults: TerminalConfig { TerminalConfig() }
}
