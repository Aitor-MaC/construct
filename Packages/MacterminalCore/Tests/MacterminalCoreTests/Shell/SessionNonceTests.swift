import Testing

@testable import MacterminalCore

@Suite struct SessionNonceTests {
  @Test func hexIs32LowercaseHexDigits() {
    let nonce = SessionNonce.random()
    #expect(nonce.hex.count == 32)
    #expect(nonce.hex.allSatisfy { "0123456789abcdef".contains($0) })
  }

  @Test func twoRandomNoncesDiffer() {
    #expect(SessionNonce.random().hex != SessionNonce.random().hex)
  }

  @Test func matchesOnlyItsOwnExactHex() {
    let nonce = SessionNonce.random()
    #expect(nonce.matches(ArraySlice(Array(nonce.hex.utf8))))
    #expect(!nonce.matches(ArraySlice(Array(SessionNonce.random().hex.utf8))))
    #expect(!nonce.matches(ArraySlice(Array(nonce.hex.dropLast().utf8))))
    #expect(!nonce.matches(ArraySlice(Array((nonce.hex + "0").utf8))))
    #expect(!nonce.matches(ArraySlice(Array(nonce.hex.uppercased().utf8))) || nonce.hex.allSatisfy(\.isNumber))
    #expect(!nonce.matches([]))
  }

  @Test func matchesASliceWithNonZeroStartIndex() {
    let nonce = SessionNonce.random()
    let bytes = Array(("xx" + nonce.hex).utf8)
    #expect(nonce.matches(bytes[2...]))
  }
}
