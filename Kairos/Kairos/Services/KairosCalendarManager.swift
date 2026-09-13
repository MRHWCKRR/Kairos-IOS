import EventKit
import Foundation
import Observation

@MainActor
@Observable
final class KairosCalendarManager {
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
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: authorizationState = .notDetermined
        case .denied: authorizationState = .denied
        case .restricted: authorizationState = .restricted
        case .fullAccess, .writeOnly: authorizationState = .authorized
        @unknown default: authorizationState = .notDetermined
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshAuthorizationState()
            return granted
        } catch {
            refreshAuthorizationState()
            return false
        }
    }

    @discardableResult
    func addEvent(title: String, start: Date, end: Date, calendar: EKCalendar? = nil, notes: String? = nil) throws -> String {
        guard authorizationState == .authorized else { throw CalendarError.notAuthorized }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = notes
        event.calendar = calendar ?? store.defaultCalendarForNewEvents
        guard event.calendar != nil else { throw CalendarError.noWritableCalendar }
        try store.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    enum CalendarError: LocalizedError {
        case notAuthorized
        case noWritableCalendar

        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Kairos does not have access to your calendar."
            case .noWritableCalendar: return "No writable calendar is available."
            }
        }
    }
}
