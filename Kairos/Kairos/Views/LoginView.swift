import SwiftUI

struct LoginView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var rememberMe = true
    @State private var isSignUpMode = false
    @State private var localErrorMessage: String?

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Spacer(minLength: 24)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(isSignUpMode ? "Create account" : "Log in")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            fieldLabel("Email")
                            TextField("you@example.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )

                            fieldLabel("Password")
                            SecureField("••••••••", text: $password)
                                .textContentType(.password)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }

                        Toggle("Remember me", isOn: $rememberMe)
                            .tint(Color.purple)
                            .foregroundStyle(.white.opacity(0.9))
                            .font(.subheadline)

                        if let message = localErrorMessage ?? session.lastErrorMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.red.opacity(0.92))
                        }

                        Button {
                            submit()
                        } label: {
                            Text(isSignUpMode ? "Sign Up" : "Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .foregroundStyle(.white)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Button {
                            isSignUpMode.toggle()
                            localErrorMessage = nil
                        } label: {
                            Text(isSignUpMode ? "Have an account? Sign In" : "Need an account? Sign Up")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 24)
                    }
                    .padding(24)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(minHeight: proxy.size.height, alignment: .center)
                }
            }
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

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }
}

#Preview {
    LoginView()
        .environment(SessionStore())
}
