import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class KairosReminderManager {
    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    private let store = EKEventStore()
    private(set) var authorizationState: AuthorizationState = .notDetermined

    init() {
        refreshAuthorizationState()
    }

    func refreshAuthorizationState() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: authorizationState = .notDetermined
        case .denied: authorizationState = .denied
        case .restricted: authorizationState = .restricted
        case .fullAccess, .writeOnly: authorizationState = .authorized
        @unknown default: authorizationState = .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToReminders()
            refreshAuthorizationState()
            return granted
        } catch {
            refreshAuthorizationState()
            return false
        }
    }

    /// Creates a reminder only when an equivalent Kairos reminder is not already present.
    /// Matching uses the title, due date components, and the Kairos marker in notes.
    @discardableResult
    func addReminderIfNeeded(title: String, dueDate: Date?, notes: String? = nil, list: EKCalendar? = nil) throws -> Bool {
        guard authorizationState == .authorized else { throw ReminderError.notAuthorized }
        guard let reminderList = list ?? store.defaultCalendarForNewReminders() else {
            throw ReminderError.noWritableList
        }

        let existing = store.reminders(matching: store.predicateForReminders(in: [reminderList])) ?? []
        let targetComponents = dueDate.map {
            Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: $0)
        }
        let duplicate = existing.contains { reminder in
            guard reminder.title == title, reminder.calendar?.calendarIdentifier == reminderList.calendarIdentifier else { return false }
            guard let notes else { return reminder.dueDateComponents == targetComponents }
            return reminder.notes == notes && reminder.dueDateComponents == targetComponents
        }
        if duplicate { return false }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = reminderList
        reminder.dueDateComponents = targetComponents
        try store.save(reminder, commit: true)
        return true
    }

    @discardableResult
    func addReminder(title: String, dueDate: Date?, notes: String? = nil, list: EKCalendar? = nil) throws -> String {
        guard authorizationState == .authorized else { throw ReminderError.notAuthorized }
        guard let reminderList = list ?? store.defaultCalendarForNewReminders() else {
            throw ReminderError.noWritableList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = reminderList
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    enum ReminderError: LocalizedError {
        case notAuthorized
        case noWritableList

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Kairos does not have access to your reminders."
            case .noWritableList: return "No writable reminder list is available."
            }
        }
    }
}
