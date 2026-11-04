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

struct KairosTask: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var completed: Bool
    var archived: Bool
    var date: String?
    var taskDescription: String? = nil
    var dueTime: String? = nil
    var parentTaskID: String? = nil
}

struct KairosScheduleEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var category: String
    var day: Int
    var start: String
    var end: String
}

// Older web plans omit flags that are false. Decode those defaults without
// making required identity/title fields optional or discarding unreadable tasks.
extension KairosBoard {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
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
    }
}

