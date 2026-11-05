import Foundation

// A read model plus narrowly-scoped commands for the web's aiWorkspace v2.
// Writes always begin with the transaction's raw document, retaining memory,
// action receipts, usage IDs, and fields added by the web client.
enum KairosAIWorkspace {
    struct Invalid: LocalizedError {
        let reason: String
        nonisolated var errorDescription: String? { reason }
        nonisolated init(_ reason: String = "This AI workspace cannot be edited safely. Review it on the web and retry.") { self.reason = reason }
    }
    struct Message: Identifiable, Equatable, Sendable {
        let id: String
        let role: String
        let content: String
        nonisolated init(id: String, role: String, content: String) { self.id = id; self.role = role; self.content = content }
    }
    struct Chat: Identifiable, Sendable {
        let id: String
        let title: String
        let projectID: String
        let messages: [Message]
        let summary: String
        let order: Double
        nonisolated init(id: String, title: String, projectID: String, messages: [Message], summary: String, order: Double) {
            self.id = id; self.title = title; self.projectID = projectID; self.messages = messages; self.summary = summary; self.order = order
        }
    }
    struct Project: Identifiable, Sendable {
        let id: String
        let title: String
        let description: String
        let sharedContext: String
        let order: Double
        nonisolated init(id: String, title: String, description: String, sharedContext: String, order: Double) {
            self.id = id; self.title = title; self.description = description; self.sharedContext = sharedContext; self.order = order
        }
    }
    struct Snapshot: Sendable {
        let chats: [Chat]
        let projects: [Project]
        let activeChatID: String?
        nonisolated init(chats: [Chat], projects: [Project], activeChatID: String?) { self.chats = chats; self.projects = projects; self.activeChatID = activeChatID }
    }
    enum Command: Sendable {
        case createChat(id: String, projectID: String)
        case renameChat(id: String, title: String)
        case deleteChat(id: String)
        case moveChat(id: String, projectID: String)
        case append(chatID: String, messages: [Message])
        case saveProject(id: String, title: String, description: String, context: String, creating: Bool)
        case deleteProject(id: String)
    }

    nonisolated private static func raw(_ value: [String: Any]?, legacy: [[String: Any]], owner: String) throws -> [String: Any] {
        if let value {
            guard value["version"] == nil || (value["version"] as? Int) == 2,
                  let chats = value["chats"] as? [[String: Any]],
                  value["projects"] == nil || value["projects"] is [[String: Any]] else { throw Invalid() }
            for items in [chats, value["projects"] as? [[String: Any]] ?? []] {
                let ids = items.compactMap { $0["id"] as? String }
                guard ids.count == items.count, ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else { throw Invalid() }
            }
            for chat in chats {
                guard let messages = chat["messages"] as? [[String: Any]], messages.allSatisfy({
                    ["user", "assistant"].contains($0["role"] as? String ?? "") && $0["content"] is String
                }) else { throw Invalid() }
            }
            return value
        }
        let id = "legacy-\(owner)"
        let migrated: [String: Any] = ["version": 2, "activeChatId": id, "projects": [], "chats": legacy.isEmpty ? [] : [["id": id, "title": "", "messages": legacy, "order": 0]]]
        return try raw(migrated, legacy: [], owner: owner)
    }

    nonisolated static func read(_ value: [String: Any]?, legacy: [[String: Any]], owner: String) throws -> Snapshot {
        let value = try raw(value, legacy: legacy, owner: owner)
        let chats = (value["chats"] as? [[String: Any]] ?? []).enumerated().map { index, item in
            let id = item["id"] as! String
            let messages = (item["messages"] as? [[String: Any]] ?? []).enumerated().map { mi, message in
                Message(id: message["id"] as? String ?? message["usageId"] as? String ?? "\(id)-\(mi)", role: message["role"] as! String, content: message["content"] as! String)
            }
            let title = (item["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return Chat(id: id, title: title.isEmpty ? String((messages.first(where: { $0.role == "user" })?.content ?? "New chat").prefix(42)) : title,
                        projectID: item["projectId"] as? String ?? "", messages: messages,
                        summary: [item["summary"] as? String, item["autoSummary"] as? String].compactMap { $0 }.joined(separator: "\n"), order: item["order"] as? Double ?? Double(index))
        }.sorted { $0.order < $1.order }
        let projects = (value["projects"] as? [[String: Any]] ?? []).enumerated().map { index, item in
            Project(id: item["id"] as! String, title: item["title"] as? String ?? "New project", description: item["description"] as? String ?? "", sharedContext: item["sharedContext"] as? String ?? "", order: item["order"] as? Double ?? Double(index))
        }.sorted { $0.order < $1.order }
        return Snapshot(chats: chats, projects: projects, activeChatID: value["activeChatId"] as? String)
    }

    nonisolated static func applying(_ command: Command, to source: [String: Any]?, legacy: [[String: Any]], owner: String) throws -> [String: Any] {
        var value = try raw(source, legacy: legacy, owner: owner)
        var chats = value["chats"] as? [[String: Any]] ?? []
        var projects = value["projects"] as? [[String: Any]] ?? []
        let now = Date().timeIntervalSince1970 * 1000
        func chatIndex(_ id: String) throws -> Int {
            guard let index = chats.firstIndex(where: { $0["id"] as? String == id }) else { throw Invalid("This conversation was deleted on another device.") }
            return index
        }
        func checkProject(_ id: String) throws {
            guard id.isEmpty || projects.contains(where: { $0["id"] as? String == id }) else { throw Invalid("This project is no longer available.") }
        }
        switch command {
        case .createChat(let id, let projectID):
            try checkProject(projectID)
            if let blank = chats.first(where: { ($0["messages"] as? [[String: Any]])?.isEmpty == true && ($0["projectId"] as? String ?? "") == projectID }) {
                value["activeChatId"] = blank["id"]
            } else {
                guard chats.count < 12, !chats.contains(where: { $0["id"] as? String == id }) else { throw Invalid("Your workspace has 12 chats. Delete a chat before creating another.") }
                chats.insert(["id": id, "title": "", "projectId": projectID, "createdAt": now, "updatedAt": now, "order": (chats.compactMap { $0["order"] as? Double }.min() ?? 0) - 1, "messages": []], at: 0)
                value["activeChatId"] = id
            }
        case .renameChat(let id, let title):
            let index = try chatIndex(id)
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 180 else { throw Invalid("Use a chat title from 1 to 180 characters.") }
            chats[index]["title"] = title; chats[index]["updatedAt"] = now
        case .deleteChat(let id):
            _ = try chatIndex(id)
            chats.removeAll { $0["id"] as? String == id }
            if value["activeChatId"] as? String == id { value["activeChatId"] = chats.first?["id"] ?? NSNull() }
        case .moveChat(let id, let projectID):
            try checkProject(projectID)
            let index = try chatIndex(id)
            chats[index]["projectId"] = projectID; chats[index]["updatedAt"] = now
        case .append(let id, let messages):
            let index = try chatIndex(id)
            var history = chats[index]["messages"] as? [[String: Any]] ?? []
            for message in messages {
                guard ["user", "assistant"].contains(message.role), !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Invalid("The message is empty or invalid.") }
                if !history.contains(where: { $0["id"] as? String == message.id || $0["usageId"] as? String == message.id }) {
                    history.append(["id": message.id, "role": message.role, "content": message.content, "timestamp": now])
                    if message.role == "user" { chats[index]["messageTotal"] = (chats[index]["messageTotal"] as? Int ?? history.count - 1) + 1 }
                }
            }
            chats[index]["messages"] = Array(history.suffix(80)); chats[index]["updatedAt"] = now
        case .saveProject(let id, let title, let description, let context, let creating):
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.utf16.count <= 80, context.utf16.count <= 3000, description.utf16.count <= 3000 else { throw Invalid("Use a project name up to 80 characters and description/context up to 3000 characters.") }
            if creating {
                guard projects.count < 20, !projects.contains(where: { $0["id"] as? String == id }) else { throw Invalid("Your workspace has reached its project limit.") }
                projects.append(["id": id, "createdAt": now, "order": now])
            }
            guard let index = projects.firstIndex(where: { $0["id"] as? String == id }) else { throw Invalid("This project was deleted on another device.") }
            projects[index]["title"] = title; projects[index]["description"] = description; projects[index]["sharedContext"] = context; projects[index]["updatedAt"] = now
        case .deleteProject(let id):
            try checkProject(id)
            projects.removeAll { $0["id"] as? String == id }
            for i in chats.indices where chats[i]["projectId"] as? String == id { chats[i]["projectId"] = "" }
        }
        value["version"] = 2; value["chats"] = chats; value["projects"] = projects
        // Refuse an oversized document, never silently evict someone else's chats.
        guard JSONSerialization.isValidJSONObject(value), try JSONSerialization.data(withJSONObject: value).count < 800_000 else { throw Invalid("This AI workspace is full. Shorten the message or remove an old chat on the web.") }
        return value
    }
}
