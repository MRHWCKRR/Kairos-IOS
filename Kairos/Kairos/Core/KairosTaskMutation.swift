import Foundation

enum KairosFieldEdit<Value> {
    case unchanged
    case set(Value)

    func apply(to current: inout Value, expected: Value?) throws where Value: Equatable {
        guard case .set(let value) = self else { return }
        if let expected, current != expected && current != value { throw KairosPlannerMerge.Conflict() }
        current = value
    }
}

struct KairosTaskPatch {
    var title: KairosFieldEdit<String> = .unchanged
    var description: KairosFieldEdit<String?> = .unchanged
    var date: KairosFieldEdit<String?> = .unchanged
    var dueTime: KairosFieldEdit<String?> = .unchanged
    var parentTaskID: KairosFieldEdit<String?> = .unchanged
}

enum KairosTaskCommand {
    case create(sectionID: String, taskID: String, title: String, parentTaskID: String?)
    case update(taskID: String, patch: KairosTaskPatch, expected: KairosTask?)
    case setCompleted(taskID: String, completed: Bool)
    case archive(taskID: String, archived: Bool)
    case delete(sectionID: String, taskID: String)
}

enum KairosTaskMutation {
    struct Invalid: LocalizedError {
        var errorDescription: String? { "This task or its section is unavailable, or its details are invalid. Review your planner and try again." }
    }

    static func apply(_ command: KairosTaskCommand, to source: [KairosBoard]) throws -> [KairosBoard] {
        var boards = source
        // Global task identity must be unique before resolving any command.
        let ids = boards.flatMap { $0.sections.flatMap { $0.tasks.map(\.id) } }
        guard Set(ids).count == ids.count else { throw Invalid() }
        switch command {
        case .create(let sectionID, let taskID, let title, let parentID):
            let matches = boards.indices.flatMap { bi in boards[bi].sections.indices.compactMap { si in
                boards[bi].sections[si].id == sectionID ? (bi, si) : nil
            } }
            guard matches.count == 1, let (bi, si) = matches.first,
                  !boards[bi].archived, !boards[bi].sections[si].archived,
                  !ids.contains(taskID), !taskID.isEmpty else { throw Invalid() }
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw Invalid() }
            if let parentID {
                guard boards[bi].sections[si].tasks.contains(where: { $0.id == parentID && !$0.archived }) else { throw Invalid() }
            }
            boards[bi].sections[si].tasks.append(KairosTask(id: taskID, title: name, completed: false, archived: false, date: nil, parentTaskID: parentID))
            if let parentID { try reconcile(&boards[bi].sections[si].tasks, startingAt: parentID, complete: false) }
        default:
            let taskID: String
            switch command {
            case .update(let id, _, _), .setCompleted(let id, _), .archive(let id, _), .delete(_, let id): taskID = id
            case .create: throw Invalid()
            }
            var location: (Int, Int, Int)?
            for bi in boards.indices {
                for si in boards[bi].sections.indices {
                    if let ti = boards[bi].sections[si].tasks.firstIndex(where: { $0.id == taskID }) { location = (bi, si, ti) }
                }
            }
            guard let (bi, si, ti) = location, !boards[bi].archived, !boards[bi].sections[si].archived else { throw Invalid() }
            var tasks = boards[bi].sections[si].tasks
            switch command {
            case .update(_, let patch, let expected):
                guard !tasks[ti].archived, expected == nil || expected?.id == taskID else { throw Invalid() }
                try patch.title.apply(to: &tasks[ti].title, expected: expected?.title)
                try patch.description.apply(to: &tasks[ti].taskDescription, expected: expected.map { $0.taskDescription })
                try patch.date.apply(to: &tasks[ti].date, expected: expected.map { $0.date })
                try patch.dueTime.apply(to: &tasks[ti].dueTime, expected: expected.map { $0.dueTime })
                try patch.parentTaskID.apply(to: &tasks[ti].parentTaskID, expected: expected.map { $0.parentTaskID })
                guard !tasks[ti].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Invalid() }
                // Existing links may point at an archived parent. Only a new
                // parent assignment requires an active target.
                if case .set(let parentID) = patch.parentTaskID, let parentID,
                   parentID != source[bi].sections[si].tasks[ti].parentTaskID {
                    guard tasks.contains(where: { $0.id == parentID && !$0.archived }) else { throw Invalid() }
                }
                // Reject dangling, cross-section and cyclic parent links.
                var seen: Set<String> = [taskID]
                var parent = tasks[ti].parentTaskID
                while let id = parent {
                    guard seen.insert(id).inserted, let item = tasks.first(where: { $0.id == id }) else { throw Invalid() }
                    parent = item.parentTaskID
                }
            case .setCompleted(_, let completed):
                guard !tasks[ti].archived else { throw Invalid() }
                tasks[ti].completed = completed
                if let parent = tasks[ti].parentTaskID { try reconcile(&tasks, startingAt: parent, complete: completed) }
            case .archive(_, let archived):
                tasks[ti].archived = archived
            case .delete(let sectionID, _):
                guard boards[bi].sections[si].id == sectionID else { throw Invalid() }
                tasks.remove(at: ti)
                // Keep children as ordinary tasks rather than dangling references.
                for i in tasks.indices where tasks[i].parentTaskID == taskID { tasks[i].parentTaskID = nil }
            case .create: throw Invalid()
            }
            boards[bi].sections[si].tasks = tasks
        }
        return boards
    }

    private static func reconcile(_ tasks: inout [KairosTask], startingAt parentID: String, complete: Bool) throws {
        var next: String? = parentID
        var seen = Set<String>()
        while let id = next {
            guard seen.insert(id).inserted, let index = tasks.firstIndex(where: { $0.id == id }) else { throw Invalid() }
            let children = tasks.filter { $0.parentTaskID == id && !$0.archived }
            tasks[index].completed = complete && !children.isEmpty && children.allSatisfy(\.completed)
            next = tasks[index].parentTaskID
        }
    }
}
