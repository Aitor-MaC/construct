import Foundation
import os

/// Prompt features chosen when a shell starts; they travel in the shell's environment so a
/// change only affects panels opened afterwards (A4) while the shared scripts stay identical.
public struct PromptOptions: Sendable, Equatable {
  public var prompt: Bool
  public var autosuggest: Bool
  public var userHost: PromptUserHost
  public var path: PromptPath
  public init(
    prompt: Bool, autosuggest: Bool, userHost: PromptUserHost = .always, path: PromptPath = .full
  ) {
    self.prompt = prompt
    self.autosuggest = autosuggest
    self.userHost = userHost
    self.path = path
  }
}

public enum ZshIntegrationError: Error, LocalizedError, Equatable {
  case directoryCreation(errno: Int32)
  case notADirectory
  case notOwned
  case insecurePermissions(mode: Int)
  case write(file: String, errno: Int32)

  public var errorDescription: String? {
    switch self {
    case .directoryCreation(let code):
      String(
        localized: "The zsh integration folder couldn’t be created (errno \(code)).",
        bundle: .localized, comment: "Error shown when the shell integration can't be installed.")
    case .notADirectory:
      String(
        localized: "The zsh integration folder is a symbolic link or isn’t a folder.",
        bundle: .localized, comment: "Error shown when the shell integration can't be installed.")
    case .notOwned:
      String(
        localized: "The zsh integration folder belongs to another user.", bundle: .localized,
        comment: "Error shown when the shell integration can't be installed.")
    case .insecurePermissions(let mode):
      String(
        localized: "The zsh integration folder has unsafe permissions (\(String(mode, radix: 8))).",
        bundle: .localized,
        comment:
          "Error shown when the shell integration can't be installed; the placeholder is the octal mode."
      )
    case .write(let file, let code):
      String(
        localized: "\(file) couldn’t be written to the zsh integration (errno \(code)).",
        bundle: .localized,
        comment:
          "Error shown when the shell integration can't be installed; the placeholders are a file name and errno."
      )
    }
  }
}

public enum ZshIntegration {
  private static let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "zsh")

  /// Writes the integration scripts into `<baseDir>/macterminal-zsh-<uid>/` and returns that
  /// directory, to be used as `ZDOTDIR`. Called before every shell spawn, so it must be cheap and
  /// safe to run concurrently; the directory is never removed because live shells keep using it.
  public static func install(in baseDir: URL) throws -> URL {
    let directory = baseDir.appending(
      path: "macterminal-zsh-\(getuid())", directoryHint: .notDirectory)
    do {
      let descriptor = try openPrivateDirectory(at: directory, owner: getuid())
      defer { close(descriptor) }
      for file in ZshScripts.files {
        try replaceAtomically(name: file.name, contents: file.contents, in: descriptor)
      }
      logger.info("install ok")
      return directory
    } catch let error as ZshIntegrationError {
      logger.error("install failed: \(String(describing: error), privacy: .public)")
      throw error
    }
  }

  /// Grey text the prompt shows after a request for the assistant; zsh can't localise it, so it
  /// travels in the environment in the app's language.
  static var aiHint: String {
    String(
      localized: "⏎ ask Apple Intelligence", bundle: .localized,
      comment:
        "Grey hint shown at the prompt after a line that starts with # or ??; pressing Return sends it to the AI. Keep the ⏎ symbol."
    )
  }

  public static func environment(
    zdotdir: URL, userZdotdir: URL?, options: PromptOptions, nonce: String
  ) -> [String: String] {
    var environment = [
      "ZDOTDIR": zdotdir.path(percentEncoded: false),
      "MACTERMINAL_PROMPT": options.prompt ? "1" : "0",
      "MACTERMINAL_AUTOSUGGEST": options.autosuggest ? "1" : "0",
      "MACTERMINAL_PROMPT_USER_HOST": options.userHost.rawValue,
      "MACTERMINAL_PROMPT_PATH": options.path.rawValue,
      "MACTERMINAL_NONCE": nonce,
      "MACTERMINAL_AI_HINT": aiHint,
      "TERM_PROGRAM": "Construct",
    ]
    if let userZdotdir {
      environment["MACTERMINAL_USER_ZDOTDIR"] = userZdotdir.path(percentEncoded: false)
    }
    return environment
  }

  /// Creates the directory if needed and opens it without following symlinks; ownership and mode
  /// are checked on the opened descriptor so the path cannot be swapped between check and use.
  static func openPrivateDirectory(at directory: URL, owner: uid_t) throws -> Int32 {
    // A trailing slash would make open(2) resolve a symlink despite O_NOFOLLOW.
    var path = directory.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }
    if mkdir(path, 0o700) != 0, errno != EEXIST {
      throw ZshIntegrationError.directoryCreation(errno: errno)
    }
    let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
    guard descriptor >= 0 else {
      if errno == ELOOP || errno == ENOTDIR { throw ZshIntegrationError.notADirectory }
      throw ZshIntegrationError.directoryCreation(errno: errno)
    }
    var info = stat()
    guard fstat(descriptor, &info) == 0 else {
      let code = errno
      close(descriptor)
      throw ZshIntegrationError.directoryCreation(errno: code)
    }
    guard info.st_uid == owner else {
      close(descriptor)
      throw ZshIntegrationError.notOwned
    }
    let mode = Int(info.st_mode & 0o777)
    guard mode == 0o700 else {
      close(descriptor)
      throw ZshIntegrationError.insecurePermissions(mode: mode)
    }
    return descriptor
  }

  /// Readers (shells starting in other panels) always see either the old or the new full file.
  private static func replaceAtomically(name: String, contents: String, in directory: Int32) throws
  {
    let temporaryName = ".\(name).\(UUID().uuidString).tmp"
    let file = openat(
      directory, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard file >= 0 else { throw ZshIntegrationError.write(file: name, errno: errno) }
    var bytes = Array(contents.utf8)[...]
    while !bytes.isEmpty {
      let written = bytes.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
      if written < 0 {
        if errno == EINTR { continue }
        let code = errno
        close(file)
        unlinkat(directory, temporaryName, 0)
        throw ZshIntegrationError.write(file: name, errno: code)
      }
      bytes = bytes.dropFirst(written)
    }
    close(file)
    guard renameat(directory, temporaryName, directory, name) == 0 else {
      let code = errno
      unlinkat(directory, temporaryName, 0)
      throw ZshIntegrationError.write(file: name, errno: code)
    }
  }
}
