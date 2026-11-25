import Foundation

@testable import MacterminalCore

/// Literales del protocolo 7777 tal como los entrega el handler de SwiftTerm: los bytes que
/// siguen a `7777;`, sin el BEL final.
enum ProtocolFixture {
  static func payload(nonce: SessionNonce?, _ fields: String...) -> ArraySlice<UInt8> {
    let all = (nonce.map { [$0.hex] } ?? []) + fields
    return ArraySlice(Array(all.joined(separator: ";").utf8))
  }

  static func payload(nonceHex: String, _ fields: String...) -> ArraySlice<UInt8> {
    ArraySlice(Array(([nonceHex] + fields).joined(separator: ";").utf8))
  }

  static func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

  static func base64(bytes: [UInt8]) -> String { Data(bytes).base64EncodedString() }
}

/// Generador determinista para el fuzz: misma semilla, mismos payloads en cada ejecución.
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
    return mixed ^ (mixed >> 31)
  }
}
