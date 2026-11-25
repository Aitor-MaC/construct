import Foundation
import MacterminalCore

public enum ShellLaunchError: Error, LocalizedError, Equatable {
  case shellNotFound(String)

  public var errorDescription: String? {
    switch self {
    case .shellNotFound(let path):
      String(
        localized: "Couldn’t open \(path). Check the shell path in Settings > Advanced.",
        bundle: .localized,
        comment:
          "Error shown when the configured shell can't be launched; the placeholder is the shell path."
      )
    }
  }
}

/// Ejecutable, argv[0] y entorno de un proceso de shell. Es la única decisión sobre qué variables
/// recibe el shell: con integración, las de `ZshIntegration` y el nonce de esta sesión; sin ella,
/// ninguna `MACTERMINAL_*` ni `ZDOTDIR`, aunque la app las haya heredado (S7).
public struct ShellLaunchPlan: Sendable {
  public struct Integration: Sendable {
    public let zdotdir: URL
    public let options: PromptOptions
    public let nonce: SessionNonce
    public init(zdotdir: URL, options: PromptOptions, nonce: SessionNonce) {
      self.zdotdir = zdotdir
      self.options = options
      self.nonce = nonce
    }
  }

  public let executable: String
  /// Con guion delante: el shell arranca como shell de login, igual que en Terminal.app.
  public let execName: String
  public let environment: [String: String]
  public let integrationAvailable: Bool

  public var environmentList: [String] { environment.map { "\($0.key)=\($0.value)" } }

  /// Solo zsh tiene scripts de integración; un reintento la desactiva a propósito.
  public static func wantsIntegration(shell: String, retryWithoutIntegration: Bool) -> Bool {
    !retryWithoutIntegration && URL(filePath: shell).lastPathComponent == "zsh"
  }

  public static func make(
    shell: String, inherited: [String: String], locale: Locale, integration: Integration?
  ) throws(ShellLaunchError) -> ShellLaunchPlan {
    guard isExecutableFile(shell) else { throw .shellNotFound(shell) }
    let userZdotdir = inherited["ZDOTDIR"].map { URL(filePath: $0, directoryHint: .notDirectory) }
    var environment = inherited.filter { key, _ in
      !key.hasPrefix("MACTERMINAL_") && key != "ZDOTDIR"
    }
    environment["TERM"] = "xterm-256color"
    environment["COLORTERM"] = "truecolor"
    environment["TERM_PROGRAM"] = "Construct"
    if environment["LANG"] == nil {
      environment["LANG"] = utf8Lang(for: locale)
    }
    if let integration {
      environment.merge(
        ZshIntegration.environment(
          zdotdir: integration.zdotdir, userZdotdir: userZdotdir, options: integration.options,
          nonce: integration.nonce.hex)
      ) { _, integrationValue in integrationValue }
    }
    return ShellLaunchPlan(
      executable: shell, execName: "-" + URL(filePath: shell).lastPathComponent,
      environment: environment, integrationAvailable: integration != nil)
  }

  private static func isExecutableFile(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return path.hasPrefix("/")
      && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
  }

  /// Sin región, o con una pareja que no existe como locale POSIX (inglés con región España),
  /// zsh quedaría en `C`; en_US.UTF-8 existe en todo macOS.
  private static func utf8Lang(for locale: Locale) -> String {
    let fallback = "en_US.UTF-8"
    guard let language = locale.language.languageCode?.identifier,
      let region = locale.region?.identifier
    else { return fallback }
    let name = "\(language)_\(region).UTF-8"
    guard let posixLocale = newlocale(LC_CTYPE_MASK, name, nil) else { return fallback }
    freelocale(posixLocale)
    return name
  }
}
