import Foundation

/// Traduce el payload de un OSC 7777 (los bytes que siguen a `7777;`, sin el BEL) a un
/// `ShellEvent`. Cualquier cosa que no sea exactamente el protocolo devuelve `nil`: el payload
/// lo controla cualquier programa que escriba en el terminal (B1).
public enum OSCParser {
  public static let maxPayloadBytes = 8192
  public static let maxDecodedBytes = 4096
  private static let separator = UInt8(ascii: ";")

  public static func parse(payload: ArraySlice<UInt8>, nonce: SessionNonce) -> ShellEvent? {
    guard payload.count <= maxPayloadBytes else { return nil }
    let fields = payload.split(separator: separator, omittingEmptySubsequences: false)
    guard fields.count >= 2, nonce.matches(fields[0]) else { return nil }
    let arguments = Array(fields.dropFirst(2))
    switch String(decoding: fields[1], as: UTF8.self) {
    case "A": return arguments.isEmpty ? .promptStarted : nil
    case "B": return arguments.isEmpty ? .inputStarted : nil
    case "C": return commandStarted(arguments)
    case "D": return commandFinished(arguments)
    case "cwd": return directoryChanged(arguments)
    case "ai": return aiRequest(arguments)
    default: return nil
    }
  }

  private static func commandStarted(_ arguments: [ArraySlice<UInt8>]) -> ShellEvent? {
    guard arguments.count == 1 || (arguments.count == 2 && arguments[1].elementsEqual("nohist".utf8)),
      let text = decodeText(arguments[0])
    else { return nil }
    // Un comando con controles (p. ej. multilínea) sigue siendo un bloque real; se pierde solo el
    // texto, que nunca debe llegar a la interfaz ni al historial.
    guard let command = stripInvisibles(text), !command.isEmpty else {
      return .commandStarted(command: nil, recordInHistory: false)
    }
    return .commandStarted(command: command, recordInHistory: arguments.count == 1)
  }

  private static func commandFinished(_ arguments: [ArraySlice<UInt8>]) -> ShellEvent? {
    guard arguments.count <= 1 else { return nil }
    let status = arguments.first.flatMap { Int32(String(decoding: $0, as: UTF8.self)) }
    return .commandFinished(exitCode: status)
  }

  private static func directoryChanged(_ arguments: [ArraySlice<UInt8>]) -> ShellEvent? {
    guard arguments.count == 1, let path = decodeText(arguments[0]), path.hasPrefix("/"),
      !path.unicodeScalars.contains(where: { $0.isForbiddenControl || $0.isBidiControl || $0.isZeroWidth })
    else { return nil }
    return .directoryChanged(URL(filePath: path, directoryHint: .isDirectory))
  }

  private static func aiRequest(_ arguments: [ArraySlice<UInt8>]) -> ShellEvent? {
    guard arguments.count == 1, let text = decodeText(arguments[0]),
      let request = stripInvisibles(text), !request.isEmpty
    else { return nil }
    return .aiRequest(request)
  }

  /// Base64 estándar estricto (sin saltos ni caracteres ajenos) y UTF-8 válido.
  private static func decodeText(_ field: ArraySlice<UInt8>) -> String? {
    guard let decoded = Data(base64Encoded: Data(field)), decoded.count <= maxDecodedBytes else {
      return nil
    }
    return String(validating: decoded, as: UTF8.self)
  }

  /// `nil` si hay controles; si no, el texto sin bidi ni caracteres de ancho cero (S1).
  private static func stripInvisibles(_ text: String) -> String? {
    var visible = String.UnicodeScalarView()
    for scalar in text.unicodeScalars {
      if scalar.isForbiddenControl { return nil }
      if scalar.isBidiControl || scalar.isZeroWidth { continue }
      visible.append(scalar)
    }
    return String(visible)
  }
}
