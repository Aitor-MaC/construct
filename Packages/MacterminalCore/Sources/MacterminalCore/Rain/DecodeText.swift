import Foundation

/// Generador pseudoaleatorio con semilla (SplitMix64). Determinista, sin estado global.
public struct SplitMix64: RandomNumberGenerator, Sendable {
  private var state: UInt64
  public init(seed: UInt64) { state = seed }
  public mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

public enum RainGlyphs {
  /// Katakana de ancho medio (U+FF66-FF9D) y `0-9 Z : . " = * + < > |`.
  public static let all: [Character] = {
    let katakana = (0xFF66...0xFF9D).compactMap { Unicode.Scalar($0).map(Character.init) }
    return katakana + Array("0123456789Z:.\"=*+<>|")
  }()
  static func random(using rng: inout some RandomNumberGenerator) -> Character {
    all[Int.random(in: 0..<all.count, using: &rng)]
  }
}

public enum DecodeText {
  /// Los primeros `floor(progress * count)` caracteres son los finales; el resto, glifos
  /// aleatorios (el espacio se conserva). Mismo largo (por `Character`) siempre.
  public static func frame(
    final: String, progress: Double, using rng: inout some RandomNumberGenerator
  ) -> String {
    if progress >= 1 { return final }
    let chars = Array(final)
    let clamped = progress.isFinite ? max(0, progress) : 0
    let fixed = min(chars.count, Int((clamped * Double(chars.count)).rounded(.down)))
    var out = String()
    for (index, char) in chars.enumerated() {
      if index < fixed || char == " " {
        out.append(char)
      } else {
        out.append(RainGlyphs.random(using: &rng))
      }
    }
    return out
  }
}
