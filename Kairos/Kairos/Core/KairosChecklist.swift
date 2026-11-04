import Foundation

enum KairosChecklist {
    nonisolated static func validate(_ items: [KairosChecklistItem]) throws {
        guard items.count <= 100, Set(items.map(\.id)).count == items.count else { throw KairosTaskMutation.Invalid() }
        for item in items {
            guard !item.id.isEmpty, item.id.utf16.count <= 120,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.title.utf16.count <= 180 else { throw KairosTaskMutation.Invalid() }
        }
    }

    nonisolated static func merge(base: [KairosChecklistItem], local: [KairosChecklistItem], remote: [KairosChecklistItem]) throws -> [KairosChecklistItem] {
        try validate(base); try validate(local); try validate(remote)
        func maps(_ items: [KairosChecklistItem]) -> [[String: Any]] {
            items.map { ["id": $0.id, "title": $0.title, "completed": $0.completed] }
        }
        let result = try KairosPlannerMerge.merge(base: ["items": maps(base)], local: ["items": maps(local)], remote: ["items": maps(remote)])
        let data = try JSONSerialization.data(withJSONObject: result["items"] ?? [])
        let items = try JSONDecoder().decode([KairosChecklistItem].self, from: data)
        try validate(items)
        return items
    }
    // Recheck after Firestore's final merge, including concurrent additions
    // and a recurrence rule enabled after this editor's snapshot.
    nonisolated static func validateMergedPlanner(base: [String: Any], merged: [String: Any]) throws {
        func tasks(_ data: [String: Any]) -> [[String: Any]] {
            (data["boards"] as? [[String: Any]] ?? []).flatMap { board in
                (board["sections"] as? [[String: Any]] ?? []).flatMap { $0["tasks"] as? [[String: Any]] ?? [] }
            }
        }
        var originals: [String: [String: Any]] = [:]
        for task in tasks(base) {
            guard let id = task["id"] as? String, originals[id] == nil else { throw KairosPlannerMerge.Conflict() }
            originals[id] = task
        }
        for task in tasks(merged) {
            let before = originals[task["id"] as? String ?? ""] ?? [:]
            let repeating = (task["recurrence"] as? [String: Any])?["enabled"] as? Bool == true
            if repeating, (task["completed"] as? Bool ?? false) != (before["completed"] as? Bool ?? false) {
                throw KairosTaskMutation.Invalid()
            }
            let oldValue = before["checklist"] ?? NSNull()
            let newValue = task["checklist"] ?? NSNull()
            guard !NSDictionary(dictionary: ["v": oldValue]).isEqual(to: ["v": newValue]) else { continue }
            let data = try JSONSerialization.data(withJSONObject: task["checklist"] ?? [])
            let items = try JSONDecoder().decode([KairosChecklistItem].self, from: data)
            try validate(items)
            if repeating && items.contains(where: \.completed) { throw KairosTaskMutation.Invalid() }
        }
    }
}
