/// When the prompt shows the `user@host` segment (`prompt-user-host`). The raw value is the one
/// written in the configuration file.
public enum PromptUserHost: String, Sendable, CaseIterable {
  case always
  /// Only in an SSH session or as root, where knowing who and where you are matters most.
  case ssh
  case never
}
