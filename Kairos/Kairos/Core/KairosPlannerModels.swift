import Foundation

struct KairosBoard: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var archived: Bool
    var sections: [KairosSection]
    var boardDescription: String? = nil
}

struct KairosSection: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var archived: Bool
    var tasks: [KairosTask]
}

struct KairosTask: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var completed: Bool
    var archived: Bool
    var date: String?
    var taskDescription: String? = nil
    var dueTime: String? = nil
    var parentTaskID: String? = nil
    var notes: String? = nil
    var priority: String? = nil
    var estimatedMinutes: Int? = nil
    var checklist: [KairosChecklistItem]? = nil
    var recurrence: KairosRecurrenceMarker? = nil
    var startTime: String? = nil
    var endTime: String? = nil
    var dueDate: String? = nil
    var reminderMinutes: Int? = nil
    var scheduleLocked: Bool? = nil
}

struct KairosScheduleEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var category: String
    var day: Int?
    var start: String
    var end: String
    var date: String? = nil
}

extension KairosScheduleEvent {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? "other"
        day = try c.decodeIfPresent(Int.self, forKey: .day)
        start = try c.decode(String.self, forKey: .start)
        end = try c.decode(String.self, forKey: .end)
        date = try c.decodeIfPresent(String.self, forKey: .date)
    }
}

// Older web plans omit flags that are false. Decode those defaults without
// making required identity/title fields optional or discarding unreadable tasks.
extension KairosBoard {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        boardDescription = try c.decodeIfPresent(String.self, forKey: .boardDescription)
        sections = try c.decodeIfPresent([KairosSection].self, forKey: .sections) ?? []
    }
}

extension KairosSection {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        tasks = try c.decodeIfPresent([KairosTask].self, forKey: .tasks) ?? []
    }
}

extension KairosTask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        completed = try c.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        date = try c.decodeIfPresent(String.self, forKey: .date)
        taskDescription = try c.decodeIfPresent(String.self, forKey: .taskDescription)
        dueTime = try c.decodeIfPresent(String.self, forKey: .dueTime)
        parentTaskID = try c.decodeIfPresent(String.self, forKey: .parentTaskID)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
        estimatedMinutes = try c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        checklist = try c.decodeIfPresent([KairosChecklistItem].self, forKey: .checklist)
        recurrence = try c.decodeIfPresent(KairosRecurrenceMarker.self, forKey: .recurrence)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes)
        scheduleLocked = try c.decodeIfPresent(Bool.self, forKey: .scheduleLocked)
    }
}


struct KairosChecklistItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var completed: Bool
}

// The complete rule remains in the raw Firestore document. Native clients only
// inspect enabled until occurrence editing is supported.
struct KairosRecurrenceMarker: Codable, Equatable, Sendable {
    var enabled: Bool = false
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }
}
