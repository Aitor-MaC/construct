import MacterminalCore
import Testing

@testable import MacterminalTerminal

@Suite struct SwiftTermColorTests {
  @Test func expandsEightBitChannels() throws {
    let rgb = try #require(RGB(hex: "#00FF41"))
    let color = rgb.terminalColor
    #expect(color.red == 0)
    #expect(color.green == 65535)
    #expect(color.blue == 16705)
  }
}
