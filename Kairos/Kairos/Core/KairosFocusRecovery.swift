import Foundation
import CryptoKit

struct KairosFocusSession: Codable, Equatable, Sendable {
    var version = 1
    let id: String
    let ownerId: String
    let planId: String?
    let createdAt: Double
    var accumulatedMs: Int64 = 0
    var startedAt: Double?
    var lastSeenAt: Double
    let target: KairosFocusTarget?
    var pending: KairosFocusLog?

    nonisolated func elapsed(now: Double) -> Int64 {
        let extra = startedAt.map { max(0, min(86_400_000, now - $0)) } ?? 0
        return min(86_400_000, accumulatedMs + Int64(extra))
    }
    nonisolated func validated(owner: String) throws -> Self {
        guard version == 1, ownerId == owner, !id.isEmpty, !owner.isEmpty, createdAt.isFinite, createdAt > 0,
              lastSeenAt.isFinite, startedAt?.isFinite != false, (0...86_400_000).contains(accumulatedMs),
              target == nil || planId != nil else { throw KairosPlannerMerge.Conflict() }
        if let pending {
            guard pending.id == id, pending.ownerId == ownerId, pending.planId == planId, pending.target == target,
                  pending.createdAt == createdAt, pending.mode == "log", (1...86400).contains(pending.seconds),
                  pending.endedAt.isFinite, pending.endedAt >= createdAt, startedAt == nil else { throw KairosPlannerMerge.Conflict() }
        }
        return self
    }
    nonisolated func recovered(now: Double) throws -> Self {
        _ = try validated(owner: ownerId)
        var copy = self
        copy.accumulatedMs = elapsed(now: min(now, max(startedAt ?? 0, lastSeenAt)))
        copy.startedAt = nil; copy.lastSeenAt = now
        return copy
    }
    nonisolated func checkpoint(now: Double, running: Bool) -> Self {
        var copy = self
        copy.accumulatedMs = elapsed(now: now); copy.lastSeenAt = now
        copy.startedAt = running && copy.accumulatedMs < 86_400_000 ? now : nil
        return copy
    }
    nonisolated func preparedLog(now: Double) throws -> Self {
        if pending != nil { return self }
        var copy = checkpoint(now: now, running: false)
        let seconds = copy.accumulatedMs / 1000
        guard seconds >= 1 else { throw KairosFocus.Failure(code: "", message: "Focus for at least one second before logging.") }
        copy.pending = .init(id: id, ownerId: ownerId, planId: planId, createdAt: createdAt, endedAt: max(createdAt, now), seconds: seconds, target: target)
        return copy
    }
}

struct KairosFocusRecoveryStore {
    let directory: URL
    nonisolated init(directory: URL) { self.directory = directory }
    nonisolated private func url(owner: String) -> URL {
        let name = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name + ".json")
    }
    nonisolated func read(owner: String) throws -> KairosFocusSession? {
        let file = url(owner: owner)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(KairosFocusSession.self, from: Data(contentsOf: file)).validated(owner: owner)
    }
    nonisolated func write(_ session: KairosFocusSession) throws {
        _ = try session.validated(owner: session.ownerId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var folder = directory; try folder.setResourceValues(values)
        let data = try JSONEncoder().encode(session)
        try data.write(to: url(owner: session.ownerId), options: .atomic)
        guard try Data(contentsOf: url(owner: session.ownerId)) == data else { throw KairosPlannerMerge.Conflict() }
    }
    nonisolated func remove(owner: String, expectedID: String) throws {
        guard let current = try read(owner: owner), current.id == expectedID else { throw KairosPlannerMerge.Conflict() }
        try FileManager.default.removeItem(at: url(owner: owner))
    }
}
