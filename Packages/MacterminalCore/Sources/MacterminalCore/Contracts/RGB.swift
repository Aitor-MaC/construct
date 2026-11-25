import Foundation

public struct RGB: Sendable, Hashable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8
  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }
  public init?(hex: String) {
    let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard digits.utf8.count == 6,
      digits.utf8.allSatisfy({
        (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
      }), let value = UInt32(digits, radix: 16)
    else { return nil }
    self.init(
      red: UInt8((value >> 16) & 255), green: UInt8((value >> 8) & 255), blue: UInt8(value & 255))
  }
  public var luminance: Double {
    func linear(_ channel: UInt8) -> Double {
      let value = Double(channel) / 255
      return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
  public func contrastRatio(with other: RGB) -> Double {
    (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
  }
}
