import Foundation

enum KairosBoardCommand {
    case renameBoard(boardID: String, title: String)
    case renameSection(sectionID: String, title: String)
    case archiveBoard(boardID: String, archived: Bool)
    case archiveSection(sectionID: String, archived: Bool)
}

enum KairosBoardMutation {
    struct Invalid: LocalizedError {
        var errorDescription: String? { "This board or section is unavailable. Restore its parent first, or refresh your planner and try again." }
    }

    static func apply(_ command: KairosBoardCommand, to source: [KairosBoard]) throws -> [KairosBoard] {
        var boards = source
        let boardIDs = boards.map(\.id)
        let sectionIDs = boards.flatMap { $0.sections.map(\.id) }
        guard Set(boardIDs).count == boardIDs.count, Set(sectionIDs).count == sectionIDs.count else { throw Invalid() }
        switch command {
        case .renameBoard(let id, let title):
            guard let bi = boards.firstIndex(where: { $0.id == id }), !boards[bi].archived else { throw Invalid() }
            boards[bi].title = try name(title)
        case .archiveBoard(let id, let archived):
            guard let bi = boards.firstIndex(where: { $0.id == id }) else { throw Invalid() }
            boards[bi].archived = archived
        case .renameSection(let id, let title):
            let (bi, si) = try section(id, in: boards)
            guard !boards[bi].sections[si].archived else { throw Invalid() }
            boards[bi].sections[si].title = try name(title)
        case .archiveSection(let id, let archived):
            let (bi, si) = try section(id, in: boards)
            boards[bi].sections[si].archived = archived
        }
        return boards
    }

    private static func name(_ title: String) throws -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw Invalid() }
        return value
    }

    private static func section(_ id: String, in boards: [KairosBoard]) throws -> (Int, Int) {
        for bi in boards.indices {
            if let si = boards[bi].sections.firstIndex(where: { $0.id == id }) {
                guard !boards[bi].archived else { throw Invalid() }
                return (bi, si)
            }
        }
        throw Invalid()
    }
}
