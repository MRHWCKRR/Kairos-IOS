import Foundation
import Observation

@Observable
@MainActor
final class SessionStore {
    var isAuthenticated = false
    var email = ""
    var lastErrorMessage: String?

    func signIn(email: String, password: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            lastErrorMessage = "Enter your email and password to continue."
            return
        }

        self.email = trimmedEmail
        lastErrorMessage = nil
        isAuthenticated = true
    }

    func signOut() {
        isAuthenticated = false
        email = ""
        lastErrorMessage = nil
    }
}
