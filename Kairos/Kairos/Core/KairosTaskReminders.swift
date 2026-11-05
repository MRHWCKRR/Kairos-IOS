import Foundation

struct KairosReminderCandidate: Sendable {
    let id: String
    let title: String
    let date: String
    let startTime: String
    let minutesBefore: Int
    nonisolated init(id: String, title: String, date: String, startTime: String, minutesBefore: Int) { self.id = id; self.title = title; self.date = date; self.startTime = startTime; self.minutesBefore = minutesBefore }
}
struct KairosPlannedReminder: Sendable, Identifiable {
    let id: String
    let title: String
    let dueAt: Date
    let startsAt: Date
    nonisolated init(id: String, title: String, dueAt: Date, startsAt: Date) { self.id = id; self.title = title; self.dueAt = dueAt; self.startsAt = startsAt }
}
enum KairosTaskReminders {
    nonisolated static func wallDate(day: String, time: String, timezone: String) -> Date? {
        guard KairosScheduleProjection.validDay(day), let minute = KairosScheduleProjection.minutes(time), TimeZone(identifier: timezone) != nil else { return nil }
        let calendar = KairosAIProposalEngine.calendar(timezone)
        let pieces = day.split(separator: "-").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var parts = DateComponents(); parts.timeZone = calendar.timeZone; parts.year = pieces[0]; parts.month = pieces[1]; parts.day = pieces[2]; parts.hour = minute / 60; parts.minute = minute % 60; parts.second = 0
        var noon = parts; noon.hour = 12; noon.minute = 0
        guard let base = calendar.date(from: noon), let prior = calendar.date(byAdding: .day, value: -1, to: base), let result = calendar.nextDate(after: prior, matching: parts, matchingPolicy: .strict, repeatedTimePolicy: .first, direction: .forward),
              KairosAIProposalEngine.dayKey(result, calendar: calendar) == day, calendar.component(.hour, from: result) == minute / 60, calendar.component(.minute, from: result) == minute % 60 else { return nil }
        return result
    }
    nonisolated static func plan(_ candidates: [KairosReminderCandidate], ownerID: String, timezone: String, now: Date, limit: Int = 50, excludingIDs: Set<String> = []) -> [KairosPlannedReminder] {
        var seen = Set<String>(), result: [KairosPlannedReminder] = []
        for candidate in candidates {
            guard (1...10080).contains(candidate.minutesBefore), let start = wallDate(day: candidate.date, time: candidate.startTime, timezone: timezone), start > now else { continue }
            let due = start.addingTimeInterval(-Double(candidate.minutesBefore) * 60)
            // If opened inside the reminder window, deliver shortly after open.
            let delivery = max(due, now.addingTimeInterval(1))
            guard delivery < start else { continue }
            let identity = [ownerID, timezone, candidate.id, candidate.date, candidate.startTime, String(candidate.minutesBefore)]
            guard let hash = try? KairosAIProposalEngine.digest(identity), seen.insert(hash).inserted else { continue }
            guard !excludingIDs.contains("kairos.task." + hash) else { continue }
            result.append(.init(id: "kairos.task." + hash, title: candidate.title, dueAt: delivery, startsAt: start))
        }
        return Array(result.sorted { ($0.dueAt, $0.id) < ($1.dueAt, $1.id) }.prefix(max(0, min(50, limit))))
    }
    nonisolated static func deliveredIDs(scheduled: [String: Double], pendingIDs: Set<String>, now: Date) -> Set<String> {
        Set(scheduled.filter { $0.value <= now.timeIntervalSince1970 && !pendingIDs.contains($0.key) }.keys)
    }
}
