import Foundation

/// Duraciones de bloque: `short` para el chip y `spoken` para VoiceOver, que lee "s" y "min" de
/// forma poco natural. Las décimas usan el separador decimal de la región (`0,4 s` o `0.4 s`).
public enum DurationFormat {
  public static func short(_ duration: Duration, locale: Locale = .current) -> String {
    switch Parts(duration) {
    case .seconds(let whole, let tenth): "\(whole)\(decimalSeparator(locale))\(tenth) s"
    case .minutes(let minutes, let seconds): "\(minutes) min \(seconds) s"
    case .hours(let hours, let minutes): "\(hours) h \(minutes) min"
    }
  }

  public static func spoken(_ duration: Duration, locale: Locale = .current) -> String {
    switch Parts(duration) {
    case .seconds(let whole, let tenth):
      "\(whole)\(decimalSeparator(locale))\(tenth) \(String(localized: "seconds", bundle: .localized, comment: "Spoken unit for a duration, plural, read by VoiceOver after a number."))"
    case .minutes(let minutes, let seconds): "\(spokenMinutes(minutes)) \(spokenSeconds(seconds))"
    case .hours(let hours, let minutes): "\(spokenHours(hours)) \(spokenMinutes(minutes))"
    }
  }

  private static func decimalSeparator(_ locale: Locale) -> String {
    locale.decimalSeparator ?? "."
  }

  private static func spokenSeconds(_ count: Int64) -> String {
    "\(count) \(count == 1 ? String(localized: "second", bundle: .localized, comment: "Spoken unit for a duration of exactly 1, read by VoiceOver.") : String(localized: "seconds", bundle: .localized, comment: "Spoken unit for a duration, plural, read by VoiceOver after a number."))"
  }

  private static func spokenMinutes(_ count: Int64) -> String {
    "\(count) \(count == 1 ? String(localized: "minute", bundle: .localized, comment: "Spoken unit for a duration of exactly 1, read by VoiceOver.") : String(localized: "minutes", bundle: .localized, comment: "Spoken unit for a duration, plural, read by VoiceOver after a number."))"
  }

  private static func spokenHours(_ count: Int64) -> String {
    "\(count) \(count == 1 ? String(localized: "hour", bundle: .localized, comment: "Spoken unit for a duration of exactly 1, read by VoiceOver.") : String(localized: "hours", bundle: .localized, comment: "Spoken unit for a duration, plural, read by VoiceOver after a number."))"
  }

  private enum Parts {
    case seconds(whole: Int64, tenth: Int64)
    case minutes(Int64, seconds: Int64)
    case hours(Int64, minutes: Int64)

    /// Redondea a décimas antes de elegir unidad, para que 59,96 s sea "1 min 0 s" y no "60,0 s".
    init(_ duration: Duration) {
      let clamped = max(duration, .zero).components
      // Tope muy por encima de cualquier duración real; evita el overflow al pasar a décimas.
      let seconds = min(clamped.seconds, Int64.max / 10 - 1)
      let tenths =
        seconds * 10 + (clamped.attoseconds + 50_000_000_000_000_000) / 100_000_000_000_000_000
      let totalSeconds = tenths / 10
      if totalSeconds < 60 {
        self = .seconds(whole: totalSeconds, tenth: tenths % 10)
      } else if totalSeconds < 3600 {
        self = .minutes(totalSeconds / 60, seconds: totalSeconds % 60)
      } else {
        self = .hours(totalSeconds / 3600, minutes: totalSeconds % 3600 / 60)
      }
    }
  }
}
