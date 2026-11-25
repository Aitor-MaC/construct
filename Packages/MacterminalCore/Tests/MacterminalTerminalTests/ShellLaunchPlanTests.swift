import Foundation
import MacterminalCore
import Testing

@testable import MacterminalTerminal

@Suite(.language("en")) struct ShellLaunchPlanTests {
  /// Lo que hereda una app lanzada desde otra sesión de Macterminal: variables que no deben
  /// filtrarse a un shell sin integración (S7).
  private let inherited = [
    "HOME": "/Users/neo", "PATH": "/usr/bin:/bin", "ZDOTDIR": "/Users/neo/.zsh",
    "MACTERMINAL_NONCE": "0123456789abcdef0123456789abcdef", "MACTERMINAL_PROMPT": "1",
    "TERM": "dumb",
  ]
  private let spanish = Locale(identifier: "es_ES")

  private func integration(_ nonce: SessionNonce) -> ShellLaunchPlan.Integration {
    ShellLaunchPlan.Integration(
      zdotdir: URL(filePath: "/tmp/macterminal-zsh-501"),
      options: PromptOptions(prompt: true, autosuggest: false), nonce: nonce)
  }

  @Test func zshWithIntegrationCarriesNonceAndUserZdotdir() throws {
    let nonce = SessionNonce.random()
    let plan = try ShellLaunchPlan.make(
      shell: "/bin/zsh", inherited: inherited, locale: spanish, integration: integration(nonce))
    #expect(plan.integrationAvailable)
    #expect(plan.executable == "/bin/zsh")
    #expect(plan.execName == "-zsh")
    #expect(plan.environment["MACTERMINAL_NONCE"] == nonce.hex)
    #expect(plan.environment["ZDOTDIR"] == "/tmp/macterminal-zsh-501")
    #expect(plan.environment["MACTERMINAL_USER_ZDOTDIR"] == "/Users/neo/.zsh")
    #expect(plan.environment["MACTERMINAL_AUTOSUGGEST"] == "0")
    #expect(plan.environment["TERM"] == "xterm-256color")
    #expect(plan.environment["COLORTERM"] == "truecolor")
    #expect(plan.environment["TERM_PROGRAM"] == "Construct")
    #expect(plan.environment["LANG"] == "es_ES.UTF-8")
    #expect(plan.environment["HOME"] == "/Users/neo")
  }

  @Test(arguments: ["/bin/bash", "/bin/zsh"])
  func withoutIntegrationNoMacterminalVariablesReachTheShell(shell: String) throws {
    let plan = try ShellLaunchPlan.make(
      shell: shell, inherited: inherited, locale: spanish, integration: nil)
    #expect(!plan.integrationAvailable)
    #expect(!plan.environment.keys.contains { $0.hasPrefix("MACTERMINAL_") })
    #expect(plan.environment["ZDOTDIR"] == nil)
    #expect(plan.environment["TERM_PROGRAM"] == "Construct")
    #expect(plan.environment["COLORTERM"] == "truecolor")
    #expect(plan.execName == "-" + URL(filePath: shell).lastPathComponent)
  }

  @Test func onlyZshOnFirstAttemptAsksForIntegration() {
    #expect(ShellLaunchPlan.wantsIntegration(shell: "/bin/zsh", retryWithoutIntegration: false))
    #expect(
      ShellLaunchPlan.wantsIntegration(
        shell: "/opt/homebrew/bin/zsh", retryWithoutIntegration: false))
    #expect(!ShellLaunchPlan.wantsIntegration(shell: "/bin/zsh", retryWithoutIntegration: true))
    #expect(!ShellLaunchPlan.wantsIntegration(shell: "/bin/bash", retryWithoutIntegration: false))
    #expect(!ShellLaunchPlan.wantsIntegration(shell: "/bin/zsh5", retryWithoutIntegration: false))
  }

  @Test func keepsAnExistingUtf8Lang() throws {
    var environment = inherited
    environment["LANG"] = "en_GB.UTF-8"
    let plan = try ShellLaunchPlan.make(
      shell: "/bin/bash", inherited: environment, locale: spanish, integration: nil)
    #expect(plan.environment["LANG"] == "en_GB.UTF-8")
  }

  /// Inglés con región España (o México) no tiene locale POSIX: zsh quedaría en `C` y ZLE rompería ñ y emoji.
  @Test(arguments: ["en_ES", "en_MX", "es_US"])
  func nonexistentLanguageRegionPairFallsBackToEnglishUtf8(identifier: String) throws {
    let plan = try ShellLaunchPlan.make(
      shell: "/bin/bash", inherited: [:], locale: Locale(identifier: identifier), integration: nil)
    #expect(plan.environment["LANG"] == "en_US.UTF-8")
  }

  @Test func existingLanguageRegionPairIsKept() throws {
    let plan = try ShellLaunchPlan.make(
      shell: "/bin/bash", inherited: [:], locale: Locale(identifier: "fr_CA"), integration: nil)
    #expect(plan.environment["LANG"] == "fr_CA.UTF-8")
  }

  @Test func localeWithoutRegionFallsBackToEnglishUtf8() throws {
    let plan = try ShellLaunchPlan.make(
      shell: "/bin/bash", inherited: [:], locale: Locale(identifier: "es"), integration: nil)
    #expect(plan.environment["LANG"] == "en_US.UTF-8")
  }

  @Test(arguments: ["/no/existe", "zsh", "", "/tmp", "/etc/hosts"])
  func rejectsShellsThatCannotBeExecuted(shell: String) {
    #expect(throws: ShellLaunchError.shellNotFound(shell)) {
      try ShellLaunchPlan.make(shell: shell, inherited: [:], locale: spanish, integration: nil)
    }
  }

  @Test func missingShellMessageNamesThePathAndTheSetting() {
    let message = ShellLaunchError.shellNotFound("/no/existe").errorDescription
    #expect(message == "Couldn’t open /no/existe. Check the shell path in Settings > Advanced.")
  }
}
