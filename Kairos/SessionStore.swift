import Foundation
import Observation
import FirebaseAuth
import FirebaseCore

@Observable
@MainActor
final class SessionStore {
    private enum StorageKey {
        static let rememberedEmail = "kairos.session.rememberedEmail"
    }

    var isAuthenticated = false
    var email = ""
    var lastErrorMessage: String?
    var remembersEmail = false
    var isBusy = false

    // Not actor-isolated: deinit runs off the main actor, so this handle
    // needs to be safely accessible from a nonisolated context. It's just
    // an opaque token used for add/remove, so this is safe.
    private nonisolated(unsafe) var authStateHandle: AuthStateDidChangeListenerHandle?

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        let defaults = UserDefaults.standard
        let rememberedEmail = defaults.string(forKey: StorageKey.rememberedEmail)
        remembersEmail = rememberedEmail != nil
        email = rememberedEmail ?? ""

        // Firebase is the single source of truth for auth state.
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            // The listener callback isn't guaranteed to run on the main actor,
            // so hop explicitly before touching main-actor-isolated state.
            Task { @MainActor in
                self.isAuthenticated = user != nil
                if let user, self.remembersEmail {
                    self.email = user.email ?? self.email
                }
            }
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    func signIn(email: String, password: String, rememberEmail: Bool) {
        Task { await authenticate(email: email, password: password, rememberEmail: rememberEmail, mode: .signIn) }
    }

    func signUp(email: String, password: String, rememberEmail: Bool) {
        Task { await authenticate(email: email, password: password, rememberEmail: rememberEmail, mode: .signUp) }
    }

    /// Used by Google Sign-In, which already has a Firebase credential by the time it calls this.
    func signIn(email: String, password: String, rememberEmail: Bool, alreadyAuthenticated: Bool) {
        applyRememberedEmail(email: email, rememberEmail: rememberEmail)
        lastErrorMessage = nil
    }

    private enum AuthMode { case signIn, signUp }

    private func authenticate(email: String, password: String, rememberEmail: Bool, mode: AuthMode) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            lastErrorMessage = "Enter your email and password to continue."
            return
        }

        isBusy = true
        lastErrorMessage = nil
        defer { isBusy = false }

        do {
            switch mode {
            case .signIn:
                _ = try await Auth.auth().signIn(withEmail: trimmedEmail, password: trimmedPassword)
            case .signUp:
                _ = try await Auth.auth().createUser(withEmail: trimmedEmail, password: trimmedPassword)
            }
            applyRememberedEmail(email: trimmedEmail, rememberEmail: rememberEmail)
            // isAuthenticated flips via the addStateDidChangeListener above.
        } catch {
            lastErrorMessage = Self.friendlyMessage(for: error)
        }
    }

    private func applyRememberedEmail(email: String, rememberEmail: Bool) {
        let defaults = UserDefaults.standard
        remembersEmail = rememberEmail
        if rememberEmail {
            defaults.set(email, forKey: StorageKey.rememberedEmail)
            self.email = email
        } else {
            defaults.removeObject(forKey: StorageKey.rememberedEmail)
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            lastErrorMessage = nil
            if !remembersEmail {
                email = ""
            }
        } catch {
            lastErrorMessage = "Sign out failed: \(error.localizedDescription)"
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        guard let code = AuthErrorCode(rawValue: nsError.code) else {
            return error.localizedDescription
        }
        switch code {
        case .wrongPassword, .invalidCredential:
            return "Incorrect email or password."
        case .userNotFound:
            return "No account found with that email."
        case .emailAlreadyInUse:
            return "That email is already in use. Try signing in instead."
        case .invalidEmail:
            return "That doesn't look like a valid email address."
        case .weakPassword:
            return "Password is too weak — use at least 6 characters."
        case .networkError:
            return "Network error — check your connection and try again."
        default:
            return error.localizedDescription
        }
    }
}
