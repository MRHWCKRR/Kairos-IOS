import Foundation
import Observation

@Observable
@MainActor
final class SessionStore {
    private enum StorageKey {
        static let isAuthenticated = "kairos.session.isAuthenticated"
        static let email = "kairos.session.email"
        static let rememberEmail = "kairos.session.rememberEmail"
    }

    var isAuthenticated = false
    var email = ""
    var lastErrorMessage: String?
    var remembersEmail = false

    init() {
        let defaults = UserDefaults.standard
        isAuthenticated = defaults.bool(forKey: StorageKey.isAuthenticated)
        email = defaults.string(forKey: StorageKey.email) ?? ""
        remembersEmail = defaults.bool(forKey: StorageKey.rememberEmail)
    }

    func signIn(email: String, password: String, rememberEmail: Bool) {
        authenticate(email: email, password: password, rememberEmail: rememberEmail)
    }

    func signUp(email: String, password: String, rememberEmail: Bool) {
        authenticate(email: email, password: password, rememberEmail: rememberEmail)
    }

    private func authenticate(
        email: String,
        password: String,
        rememberEmail: Bool
    ) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            lastErrorMessage = "Enter your email and password to continue."
            return
        }

        self.email = trimmedEmail
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: StorageKey.isAuthenticated)
        defaults.set(rememberEmail, forKey: StorageKey.rememberEmail)
        remembersEmail = rememberEmail

        if rememberEmail {
            defaults.set(trimmedEmail, forKey: StorageKey.email)
        } else {
            defaults.removeObject(forKey: StorageKey.email)
            self.email = ""
        }

        lastErrorMessage = nil
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        lastErrorMessage = nil
        UserDefaults.standard.set(false, forKey: StorageKey.isAuthenticated)
        if !remembersEmail {
            email = ""
        }
    }
}
