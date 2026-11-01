import Foundation

enum KairosPlannerMerge {
    struct Conflict: LocalizedError {
        nonisolated var errorDescription: String? { "This item changed on another device. Review the latest planner before retrying." }
    }

    // Like the web planner: apply only changes made since the editor's baseline.
    // Unknown fields stay in remote, including task metadata absent from iOS models.
    nonisolated static func merge(base: [String: Any], local: [String: Any], remote: [String: Any]) throws -> [String: Any] {
        try validate(base); try validate(local); try validate(remote)
        let result = try mergeValue(base, local, remote) as? [String: Any] ?? [:]
        try validate(result)
        return result
    }

    nonisolated private static func equal(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        default: return NSDictionary(dictionary: ["v": lhs!]).isEqual(to: ["v": rhs!])
        }
    }

    nonisolated static func applyingKnownEdits(base: [String: Any], local: [String: Any], to raw: [String: Any]) throws -> [String: Any] {
        try validate(base); try validate(local); try validate(raw)
        return try applyingValue(base, local, raw) as? [String: Any] ?? [:]
    }

    // Expand the native model's edits into a complete local document before
    // comparing it with the complete server document. Metadata omitted by a
    // native Codable model is not itself a competing change.
    nonisolated private static func applyingValue(_ base: Any?, _ local: Any?, _ raw: Any?) throws -> Any? {
        if equal(base, local) { return raw }
        guard let local else { return nil }
        if let b = base as? [[String: Any]], let l = local as? [[String: Any]], let r = raw as? [[String: Any]],
           (b + l + r).allSatisfy({ ($0["id"] as? String)?.isEmpty == false }) {
            let bm = Dictionary(uniqueKeysWithValues: b.map { ($0["id"] as! String, $0) })
            let rm = Dictionary(uniqueKeysWithValues: r.map { ($0["id"] as! String, $0) })
            return try l.compactMap { item in
                let id = item["id"] as! String
                return try applyingValue(bm[id], item, rm[id])
            }
        }
        if let l = local as? [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var result = raw as? [String: Any] ?? [:]
            for key in Set(b.keys).union(l.keys) { result[key] = try applyingValue(b[key], l[key], result[key]) }
            return result
        }
        return local
    }

    nonisolated private static func mergeValue(_ base: Any?, _ local: Any?, _ remote: Any?) throws -> Any? {
        if equal(local, base) { return remote }
        if equal(remote, base) || equal(local, remote) { return local }
        if base != nil && (local == nil || remote == nil) { throw Conflict() }

        if let b = base as? [[String: Any]], let l = local as? [[String: Any]], let r = remote as? [[String: Any]],
           (b + l + r).allSatisfy({ ($0["id"] as? String)?.isEmpty == false }) {
            let bm = Dictionary(uniqueKeysWithValues: b.map { ($0["id"] as! String, $0) })
            let lm = Dictionary(uniqueKeysWithValues: l.map { ($0["id"] as! String, $0) })
            let rm = Dictionary(uniqueKeysWithValues: r.map { ($0["id"] as! String, $0) })
            let bi = b.map { $0["id"] as! String }, li = l.map { $0["id"] as! String }, ri = r.map { $0["id"] as! String }
            let common = Set(bi).intersection(li).intersection(ri)
            let bo = bi.filter { common.contains($0) }, lo = li.filter { common.contains($0) }, ro = ri.filter { common.contains($0) }
            if lo != bo && ro != bo && lo != ro { throw Conflict() }
            let order = bi == li ? ri : li
            var seen = Set<String>()
            return try (order + ri + li).filter { seen.insert($0).inserted }.compactMap { id in
                try mergeValue(bm[id], lm[id], rm[id])
            }
        }

        if let l = local as? [String: Any], let r = remote as? [String: Any], base == nil || base is [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var result: [String: Any] = [:]
            for key in Set(b.keys).union(l.keys).union(r.keys) {
                result[key] = try mergeValue(b[key], l[key], r[key])
            }
            return result
        }
        throw Conflict()
    }

    nonisolated private static func validate(_ value: Any) throws {
        if let map = value as? [String: Any] {
            for child in map.values { try validate(child) }
        } else if let list = value as? [Any] {
            let ids = list.compactMap { ($0 as? [String: Any])?["id"] as? String }
            if !ids.isEmpty && (ids.count != list.count || Set(ids).count != ids.count || ids.contains("")) { throw Conflict() }
            for child in list { try validate(child) }
        }
    }
}
