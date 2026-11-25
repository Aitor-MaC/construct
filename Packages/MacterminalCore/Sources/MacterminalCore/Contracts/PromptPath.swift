/// How the prompt shows the current folder (`prompt-path`). The raw value is the one written in
/// the configuration file.
public enum PromptPath: String, Sendable, CaseIterable {
  /// `~/Proyectos Apps/Macterminal`, cut on the left with `…/` when it doesn't fit.
  case full
  /// `~/P/Macterminal`: every folder but the last reduced to its first letter.
  case short
}
