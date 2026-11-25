import Foundation

/// ⌘+ / ⌘− / ⌘0: pasos de 1 pt dentro del rango que acepta `font-size` (10-24 pt).
public enum FontSizeStep {
  public enum Change: Sendable { case increase, decrease, reset }

  public static let range: ClosedRange<Double> = 10...24

  /// Tamaño resultante en pt; `nil` si el cambio no lo mueve (tope alcanzado o ya por defecto),
  /// para que la acción quede deshabilitada en el menú.
  public static func apply(_ change: Change, to size: Double) -> Double? {
    let target: Double
    switch change {
    case .increase: target = min(range.upperBound, size.rounded(.down) + 1)
    case .decrease: target = max(range.lowerBound, size.rounded(.up) - 1)
    case .reset: target = TerminalConfig.defaults.fontSize
    }
    return target == size ? nil : target
  }

  /// Valor para `ConfigStore.set(.fontSize, …)`: los pasos son siempre enteros.
  public static func configValue(_ size: Double) -> String {
    String(Int(size.rounded()))
  }
}
