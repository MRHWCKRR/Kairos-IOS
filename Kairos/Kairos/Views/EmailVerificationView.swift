import SwiftUI

struct EmailVerificationView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                KairosIcon("envelope.badge.shield.half.filled", size: 48)
                    .foregroundStyle(KairosColors.accent)
                    .accessibilityHidden(true)
                Text("Verify your email").font(.title2.bold())
                Text("Open the verification link sent to \(session.email) to access your planner.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if let message = session.verificationMessage {
                    Text(message).font(.footnote).multilineTextAlignment(.center)
                }
                if let error = session.lastErrorMessage {
                    Label(error, sharedIcon: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.red)
                }
                Button("I've verified my email") { Task { await session.refreshVerification() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isBusy)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, Int(ceil(session.verificationCooldownUntil.timeIntervalSince(context.date))))
                    Button(remaining > 0 ? "Resend in \(remaining)s" : "Resend verification email") { session.resendVerification() }
                        .disabled(session.isBusy || remaining > 0)
                }
                Button("Wrong email? Sign out") { session.signOut() }
                    .disabled(session.isBusy)
                if session.isBusy { ProgressView().accessibilityLabel("Checking your account") }
            }
            .padding(28)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
}

