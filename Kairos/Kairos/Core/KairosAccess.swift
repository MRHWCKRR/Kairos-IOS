import Foundation

enum KairosAccess {
    nonisolated static func canEnterWorkspace(userID: String?, emailVerified: Bool) -> Bool {
        guard let userID, !userID.isEmpty else { return false }
        return emailVerified
    }
}
