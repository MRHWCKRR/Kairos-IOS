import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = true
    @State private var isSignUpMode = false
    @State private var localErrorMessage: String?
    @State private var isGoogleSigningIn = false

    private let accent = Color(red: 0.53, green: 0.36, blue: 0.94) // warm violet

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 40)

                branding

                VStack(spacing: 6) {
                    Text(isSignUpMode ? "Create your account" : "Welcome back")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(isSignUpMode ? "Let's get your schedule set up." : "Good to see you again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 22) {
                    googleButton

                    divider

                    VStack(spacing: 14) {
                        inputField(
                            label: "Email address",
                            placeholder: "you@example.com",
                            text: $email,
                            isSecure: false
                        )

                        inputField(
                            label: "Password",
                            placeholder: "••••••••",
                            text: $password,
                            isSecure: true
                        )
                    }

                    checkboxRow

                    if let message = localErrorMessage ?? session.lastErrorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.footnote)
                            Text(message)
                                .font(.footnote)
                        }
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submit()
                    } label: {
                        Text(isSignUpMode ? "Sign Up" : "Sign In")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                    }
                    .foregroundStyle(.white)
                    .background(accent, in: Capsule())
                    .shadow(color: accent.opacity(0.35), radius: 14, y: 6)

                    Button {
                        isSignUpMode.toggle()
                        localErrorMessage = nil
                    } label: {
                        Text(isSignUpMode ? "Already have an account? " : "New here? ")
                            .foregroundStyle(.secondary)
                        +
                        Text(isSignUpMode ? "Sign In" : "Create one")
                            .foregroundStyle(accent)
                            .fontWeight(.semibold)
                    }
                    .font(.footnote)
                    .buttonStyle(.plain)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 440)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
    }

    private var branding: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)

            Text("Kairos")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private var googleButton: some View {
        Button {
            handleGoogleSignIn()
        } label: {
            if isGoogleSigningIn {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 44)
                .background(Color(.systemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            } else {
                Image("GoogleSignInButton")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 44)
            }
        }
        .buttonStyle(.plain)
        .disabled(isGoogleSigningIn)
    }
    
    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            Text("OR")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(.tertiary)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }
    
    
    private var checkboxRow: some View {
        Button {
            rememberMe.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: rememberMe ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(rememberMe ? accent : Color.secondary.opacity(0.5))

                Text("Remember me")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func inputField(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(isSecure ? .default : .emailAddress)
            .textContentType(isSecure ? .password : .emailAddress)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            localErrorMessage = "Enter an email and password."
            return
        }

        localErrorMessage = nil

        if isSignUpMode {
            session.signUp(email: trimmedEmail, password: trimmedPassword, rememberEmail: rememberMe)
        } else {
            session.signIn(email: trimmedEmail, password: trimmedPassword, rememberEmail: rememberMe)
        }
    }

    private func handleGoogleSignIn() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            localErrorMessage = "Missing Firebase client ID."
            return
        }

        guard let presentingViewController = UIApplication.shared.topMostViewController else {
            localErrorMessage = "Unable to open Google sign-in."
            return
        }

        localErrorMessage = nil
        isGoogleSigningIn = true
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error {
                isGoogleSigningIn = false
                localErrorMessage = error.localizedDescription
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                isGoogleSigningIn = false
                localErrorMessage = "Google sign-in did not return an ID token."
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { authResult, authError in
                isGoogleSigningIn = false

                if let authError {
                    localErrorMessage = authError.localizedDescription
                    return
                }

                let signedInEmail = authResult?.user.email ?? user.profile?.email ?? ""
                Task { @MainActor in
                    session.signIn(email: signedInEmail, password: idToken, rememberEmail: true, alreadyAuthenticated: true)
                }
            }
        }
    }
}

private extension UIApplication {
    var topMostViewController: UIViewController? {
        guard let scene = connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let rootViewController = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return nil
        }
        return rootViewController.topMostViewController
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topMostViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topMostViewController
        }
        return self
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}

#Preview("Dark") {
    LoginView()
        .environment(SessionStore())
        .preferredColorScheme(.dark)
}
