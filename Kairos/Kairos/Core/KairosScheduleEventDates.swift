import Foundation

extension KairosScheduleEvent {
    var scheduleLabel: String {
        if let date { return date }
        guard let day else { return "No date" }
        if (0...6).contains(day) { return Calendar(identifier: .gregorian).weekdaySymbols[day] }
        return "Day \(day)"
    }

    func scheduledDay(relativeTo base: Date, calendar: Calendar = .current) -> Date? {
        if let date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let value = formatter.date(from: date), formatter.string(from: value) == date else { return nil }
            return value
        }
        guard let day, day >= 0 else { return nil }
        let start = calendar.startOfDay(for: base)
        if day > 6 { return calendar.date(byAdding: .day, value: day - 1, to: start) }
        let current = calendar.component(.weekday, from: base) - 1
        return calendar.date(byAdding: .day, value: (day - current + 7) % 7, to: start)
    }
}
