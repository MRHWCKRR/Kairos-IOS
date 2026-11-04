import Foundation

enum KairosChecklist {
    static func validate(_ items: [KairosChecklistItem]) throws {
        guard items.count <= 100, Set(items.map(\.id)).count == items.count else { throw KairosTaskMutation.Invalid() }
        for item in items {
            guard !item.id.isEmpty, item.id.utf16.count <= 120,
                  !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.title.utf16.count <= 180 else { throw KairosTaskMutation.Invalid() }
        }
    }

    static func merge(base: [KairosChecklistItem], local: [KairosChecklistItem], remote: [KairosChecklistItem]) throws -> [KairosChecklistItem] {
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
}
