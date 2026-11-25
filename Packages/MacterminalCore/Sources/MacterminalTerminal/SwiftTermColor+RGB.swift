import MacterminalCore
import SwiftTerm

extension RGB {
  public var terminalColor: SwiftTerm.Color {
    SwiftTerm.Color(red: UInt16(red) * 257, green: UInt16(green) * 257, blue: UInt16(blue) * 257)
  }
}
