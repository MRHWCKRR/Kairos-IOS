import Foundation
import CoreFoundation

/// Read compatibility for metadata exported as timestamp component maps.
/// Native Firestore Timestamp values are handled directly by the repository.
enum KairosPlannerTimestamp {
    static func date(from value: Any?) -> Date? {
        if let date = value as? Date { return valid(date) }
        if let string = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return valid(date) }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string).flatMap(valid)
        }
        guard let map = value as? [String: Any],
              let seconds = integer(map["seconds"] ?? map["_seconds"]),
              seconds >= -62_135_596_800, seconds <= 253_402_300_799 else { return nil }
        let rawNanos = map["nanoseconds"] ?? map["_nanoseconds"]
        let nanos: Double
        if rawNanos == nil { nanos = 0 }
        else {
            guard let parsed = integer(rawNanos), parsed >= 0, parsed < 1_000_000_000 else { return nil }
            nanos = parsed
        }
        return valid(Date(timeIntervalSince1970: seconds + nanos / 1_000_000_000))
    }

    private static func integer(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded(.towardZero) == value else { return nil }
        return value
    }

    private static func valid(_ date: Date) -> Date? {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, seconds >= -62_135_596_800, seconds < 253_402_300_800 else { return nil }
        return date
    }
}
