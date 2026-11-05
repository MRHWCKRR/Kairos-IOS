import Foundation
import JavaScriptCore

enum KairosSearchStatus: String, CaseIterable, Sendable {
    case all = "All", unfinished = "Unfinished", overdue = "Overdue", completed = "Completed"
    nonisolated var engineValue: String { rawValue.lowercased() }
}
struct KairosSearchTarget: Codable, Equatable, Sendable {
    let kind: String
    let boardId: String?
    let sectionId: String?
    let taskId: String?
    let occurrenceDate: String?
}
struct KairosSearchRow: Codable, Identifiable, Sendable {
    let key: String
    let kind: String
    let title: String
    let path: String
    let label: String
    let assignmentTitle: String?
    let target: KairosSearchTarget
    let completed: Bool
    let overdue: Bool
    let date: String?
    let dateKind: String?
    let occurrenceDate: String?
    var id: String { key }
}
struct KairosSearchResults: Decodable, Sendable {
    let rows: [KairosSearchRow]
    let total: Int
}
struct KairosSearchIndex: Sendable {
    let json: String
    let from: String
    let to: String
    let today: String
    nonisolated init(json: String, from: String, to: String, today: String) { self.json = json; self.from = from; self.to = to; self.today = today }
}
enum KairosPlannerSearch {
    struct Unavailable: LocalizedError {
        nonisolated var errorDescription: String? { "Search could not read this planner. Retry after your planner has loaded." }
    }
    nonisolated static func inputJSON(_ plan: [String: Any]) throws -> String {
        var boards = try KairosAIProposalEngine.maps(plan["boards"])
        for bi in boards.indices {
            var sections = try KairosAIProposalEngine.maps(boards[bi]["sections"])
            for si in sections.indices {
                sections[si]["tasks"] = try KairosAIProposalEngine.maps(sections[si]["tasks"]).map { task in
                    var value = task.filter { ["id", "title", "archived", "completed", "date", "dueDate", "notes", "assignmentId", "startTime", "endTime", "estimatedMinutes"].contains($0.key) }
                    if value["notes"] == nil { value["notes"] = task["taskDescription"] }
                    if task["recurrence"] != nil { value["recurrence"] = try KairosRecurrence.input(task)["recurrence"] }
                    return value
                }
                sections[si] = sections[si].filter { ["id", "title", "archived", "tasks"].contains($0.key) }
            }
            boards[bi] = boards[bi].filter { ["id", "title", "archived"].contains($0.key) }
            boards[bi]["sections"] = sections
        }
        return try KairosTouchSchedule.json(["boards": boards])
    }
    nonisolated private static func run(_ args: [String: Any]) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let context = JSContext() else { throw Unavailable() }
        for name in ["recurrence-engine", "planner-search-engine"] {
            guard let url = bundle.url(forResource: name, withExtension: "js") else { throw Unavailable() }
            context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
            guard context.exception == nil else { throw Unavailable() }
        }
        let output = context.objectForKeyedSubscript("kairosPlannerSearchRequest")?.call(withArguments: [try KairosTouchSchedule.json(args)])?.toString()
        guard context.exception == nil, let data = output?.data(using: .utf8) else { throw Unavailable() }
        return data
    }
    nonisolated static func build(planJSON: String, today: String) throws -> KairosSearchIndex {
        let data = try run(["mode": "index", "state": KairosTouchSchedule.object(planJSON), "today": today])
        guard let json = String(data: data, encoding: .utf8), let map = try JSONSerialization.jsonObject(with: data) as? [String: Any], let from = map["from"] as? String, let to = map["to"] as? String else { throw Unavailable() }
        return .init(json: json, from: from, to: to, today: today)
    }
    nonisolated static func search(_ index: KairosSearchIndex, query: String, status: KairosSearchStatus) throws -> KairosSearchResults {
        let data = try run(["mode": "search", "index": KairosTouchSchedule.object(index.json), "query": query, "status": status.engineValue])
        return try JSONDecoder().decode(KairosSearchResults.self, from: data)
    }
}
