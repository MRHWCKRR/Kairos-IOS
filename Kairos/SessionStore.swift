import Foundation
import Observation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

@Observable
@MainActor
final class SessionStore {
    private(set) var userID: String?
    private(set) var emailVerified = false
    var isAuthenticated: Bool { KairosAccess.canEnterWorkspace(userID: userID, emailVerified: emailVerified) }
    var needsEmailVerification: Bool { userID != nil && !emailVerified }
    var email = ""
    var lastErrorMessage: String?
    var verificationMessage: String?
    var remembersEmail = false
    var isBusy = false
    private(set) var verificationCooldownUntil = Date.distantPast
    private nonisolated var authStateHandle: AuthStateDidChangeListenerHandle?
    private let rememberedEmailKey = "kairos.session.rememberedEmail"

    init() {
        KairosFirebase.configure()
        let remembered = UserDefaults.standard.string(forKey: rememberedEmailKey)
        remembersEmail = remembered != nil
        email = remembered ?? ""
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self, Auth.auth().currentUser?.uid == user?.uid else { return }
                self.apply(user)
            }
        }
    }

    deinit {
        if let authStateHandle { Auth.auth().removeStateDidChangeListener(authStateHandle) }
    }

    private func apply(_ user: User?) {
        if userID != user?.uid {
            _ = FocusTimerCoordinator.shared.stopAndReset()
            lastErrorMessage = nil
            verificationMessage = nil
        }
        userID = user?.uid
        emailVerified = user?.isEmailVerified == true
        email = user?.email ?? (UserDefaults.standard.string(forKey: rememberedEmailKey) ?? "")
        verificationCooldownUntil = user.map {
            UserDefaults.standard.object(forKey: "kairos.verification.cooldown.\($0.uid)") as? Date ?? .distantPast
        } ?? .distantPast
    }

    func signIn(email: String, password: String, rememberEmail: Bool) {
        guard !isBusy else { return }
        isBusy = true
        Task { await authenticate(email: email, password: password, rememberEmail: rememberEmail, signUp: false) }
    }

    func signUp(email: String, password: String, rememberEmail: Bool) {
        guard !isBusy else { return }
        isBusy = true
        Task { await authenticate(email: email, password: password, rememberEmail: rememberEmail, signUp: true) }
    }

    func completeGoogleSignIn(email: String, rememberEmail: Bool) {
        applyRememberedEmail(email, remember: rememberEmail)
        apply(Auth.auth().currentUser)
    }

    private func authenticate(email: String, password: String, rememberEmail: Bool, signUp: Bool) async {
        defer { isBusy = false }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            lastErrorMessage = "Enter your email and password to continue."
            return
        }
        lastErrorMessage = nil
        do {
            let result: AuthDataResult
            if signUp { result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password) }
            else { result = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password) }
            applyRememberedEmail(trimmedEmail, remember: rememberEmail)
            apply(result.user)
            if signUp && !result.user.isEmailVerified { await sendVerification(to: result.user) }
        } catch { lastErrorMessage = Self.friendlyMessage(for: error) }
    }

    func refreshVerification() async {
        guard !isBusy, let user = Auth.auth().currentUser else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await user.reload()
            guard Auth.auth().currentUser?.uid == user.uid else { return }
            if user.isEmailVerified { _ = try await user.getIDToken(forcingRefresh: true) }
            guard Auth.auth().currentUser?.uid == user.uid else { return }
            apply(user)
            lastErrorMessage = nil
            if !user.isEmailVerified { verificationMessage = "Your email is not verified yet. Open the link in your inbox, then check again." }
        } catch {
            guard Auth.auth().currentUser?.uid == user.uid else { return }
            lastErrorMessage = Self.friendlyMessage(for: error)
            if let code = AuthErrorCode(rawValue: (error as NSError).code), [.userNotFound, .userDisabled, .userTokenExpired, .invalidUserToken].contains(code) { signOut() }
        }
    }

    func resendVerification() {
        guard !isBusy, Date() >= verificationCooldownUntil, let user = Auth.auth().currentUser, !user.isEmailVerified else { return }
        isBusy = true
        Task { await sendVerification(to: user); isBusy = false }
    }

    private func sendVerification(to user: User) async {
        verificationCooldownUntil = Date().addingTimeInterval(60)
        UserDefaults.standard.set(verificationCooldownUntil, forKey: "kairos.verification.cooldown.\(user.uid)")
        do {
            try await user.sendEmailVerification()
            guard Auth.auth().currentUser?.uid == user.uid else { return }
            lastErrorMessage = nil
            verificationMessage = "Verification email sent. Check your inbox and spam folder."
        } catch {
            guard Auth.auth().currentUser?.uid == user.uid else { return }
            lastErrorMessage = Self.friendlyMessage(for: error)
        }
    }

    private func applyRememberedEmail(_ email: String, remember: Bool) {
        remembersEmail = remember
        if remember { UserDefaults.standard.set(email, forKey: rememberedEmailKey) }
        else { UserDefaults.standard.removeObject(forKey: rememberedEmailKey) }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            apply(nil)
        } catch { lastErrorMessage = "Sign out failed. Please try again." }
    }

    private static func friendlyMessage(for error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .wrongPassword, .invalidCredential: return "Incorrect email or password."
        case .userNotFound: return "No account found with that email."
        case .emailAlreadyInUse: return "That email is already in use. Try signing in instead."
        case .invalidEmail: return "Enter a valid email address."
        case .weakPassword: return "Choose a stronger password."
        case .networkError: return "Check your connection and try again."
        case .tooManyRequests: return "Too many attempts. Please wait before trying again."
        default: return "Kairos could not complete this request. Please try again."
        }
    }
}

