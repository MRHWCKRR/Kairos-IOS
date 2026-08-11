import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var isSignUpMode = false
    @State private var localErrorMessage: String?

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        KairosLogo(size: 72)
                        Spacer()
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(isSignUpMode ? "Create account" : "Welcome back")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(isSignUpMode ? "Join Kairos to get started." : "Log in to access your schedule.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .padding(.top, 24)

                    VStack(spacing: 12) {
                        SocialLoginButton(
                            title: "Continue with Google",
                            systemImage: "g.circle.fill",
                            action: {
                                handleGoogleSignIn()
                            }
                        )

                        SocialLoginButton(
                            title: "Continue with GitHub",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            action: {
                                localErrorMessage = "GitHub sign-in is not wired up yet."
                            }
                        )

                        SocialLoginButton(
                            title: "Continue with Microsoft",
                            systemImage: "square.grid.2x2.fill",
                            action: {
                                localErrorMessage = "Microsoft sign-in is not wired up yet."
                            }
                        )
                    }

                    Separator(label: "OR SECURELY WITH EMAIL")

                    VStack(alignment: .leading, spacing: 12) {
                        FieldLabel("Email Address")
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        FieldLabel("Password")
                        SecureField("••••••••", text: $password)
                            .textContentType(.password)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let message = localErrorMessage ?? session.lastErrorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.9))
                    }

                    Toggle("Remember me", isOn: $rememberMe)
                        .tint(.white)
                        .foregroundStyle(.white)

                    Button {
                        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            localErrorMessage = "Please fill in all fields."
                            return
                        }

                        localErrorMessage = nil
                        if isSignUpMode {
                            session.signUp(email: email, password: password, rememberEmail: rememberMe)
                        } else {
                            session.signIn(email: email, password: password, rememberEmail: rememberMe)
                        }
                    } label: {
                        Text(isSignUpMode ? "Sign Up" : "Sign In")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        isSignUpMode.toggle()
                    } label: {
                        Text(isSignUpMode ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .frame(maxWidth: .infinity)
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .buttonStyle(.plain)
                }
                .padding(24)
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if email.isEmpty {
                email = session.email
                rememberMe = !session.email.isEmpty
            }
        }
    }

    private var background: some View {
        Color.black
        .ignoresSafeArea()
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
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
            if let error {
                localErrorMessage = error.localizedDescription
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                localErrorMessage = "Google sign-in did not return an ID token."
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { authResult, authError in
                if let authError {
                    localErrorMessage = authError.localizedDescription
                    return
                }

                let signedInEmail = authResult?.user.email ?? user.profile?.email ?? ""
                Task { @MainActor in
                    session.signIn(email: signedInEmail, password: idToken, rememberEmail: true)
                    session.lastErrorMessage = nil
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}

private struct SocialLoginButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 18)

                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
        }
    }
}

private struct Separator: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)

            Text(label)
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.55))

            Rectangle()
                .fill(.white.opacity(0.14))
                .frame(height: 1)
        }
    }
}

private struct FieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .background(Color(red: 0.54, green: 0.23, blue: 0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct KairosLogo: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let scaleX = canvasSize.width / 100
            let scaleY = canvasSize.height / 100
            let lineWidth = 15 * min(scaleX, scaleY)
            let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

            var left = Path()
            left.move(to: CGPoint(x: 24.5 * scaleX, y: 85 * scaleY))
            left.addLine(to: CGPoint(x: 50.5 * scaleX, y: 15 * scaleY))

            var right = Path()
            right.move(to: CGPoint(x: 49.5 * scaleX, y: 85 * scaleY))
            right.addLine(to: CGPoint(x: 75.5 * scaleX, y: 15 * scaleY))

            context.stroke(
                left,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.85, green: 0.71, blue: 0.99), location: 0),
                        .init(color: Color(red: 0.75, green: 0.55, blue: 0.98), location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                ),
                style: strokeStyle
            )

            context.stroke(
                right,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(red: 0.66, green: 0.34, blue: 0.97), location: 0),
                        .init(color: Color(red: 0.49, green: 0.13, blue: 0.81), location: 1)
                    ]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                ),
                style: strokeStyle
            )
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.54, green: 0.23, blue: 0.92).opacity(0.35), radius: 18, x: 0, y: 10)
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
