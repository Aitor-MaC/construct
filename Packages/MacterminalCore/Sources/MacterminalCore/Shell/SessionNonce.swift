/// Secreto de 128 bits por proceso de shell. Solo las marcas 7777 que lo llevan cambian el estado
/// de la app; la salida de los programas no lo conoce (B1).
public struct SessionNonce: Sendable {
  private static let byteCount = 16
  private static let hexDigits = Array("0123456789abcdef".utf8)

  /// Representación ASCII en hexadecimal minúsculo: lo que viaja en el OSC y lo que se compara.
  private let hexBytes: [UInt8]

  private init(hexBytes: [UInt8]) { self.hexBytes = hexBytes }

  /// `SystemRandomNumberGenerator` es criptográficamente seguro en Darwin (arc4random).
  public static func random() -> SessionNonce {
    var generator = SystemRandomNumberGenerator()
    var hexBytes: [UInt8] = []
    hexBytes.reserveCapacity(byteCount * 2)
    for _ in 0..<byteCount {
      let byte = UInt8.random(in: .min ... .max, using: &generator)
      hexBytes.append(hexDigits[Int(byte >> 4)])
      hexBytes.append(hexDigits[Int(byte & 0x0F)])
    }
    return SessionNonce(hexBytes: hexBytes)
  }

  public var hex: String { String(decoding: hexBytes, as: UTF8.self) }

  /// Tiempo constante respecto al contenido: recorre siempre los 32 bytes y no sale en el primer
  /// fallo, para que un programa no pueda adivinar el nonce midiendo cuánto tarda el rechazo.
  /// La longitud no es secreta (siempre 32), así que se descarta antes.
  public func matches(_ candidate: ArraySlice<UInt8>) -> Bool {
    guard candidate.count == hexBytes.count else { return false }
    var difference: UInt8 = 0
    for (received, expected) in zip(candidate, hexBytes) {
      difference |= received ^ expected
    }
    return difference == 0
  }
}
