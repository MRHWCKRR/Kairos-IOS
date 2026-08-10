import SwiftUI

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
                                localErrorMessage = "Google sign-in is not wired up yet."
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
                        session.signIn(email: email, password: password)
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
    }

    private var background: some View {
        Color.black
        .ignoresSafeArea()
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
