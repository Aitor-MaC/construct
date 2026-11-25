import Foundation
import MacterminalCore

extension Bundle {
  static var localized: Bundle { Localization.bundle(.module) }
}
