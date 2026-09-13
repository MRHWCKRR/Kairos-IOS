import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @Environment(SessionStore.self) private var session
    @State private var planRepo = StudyPlanRepository()
    @State private var profileRepo = UserProfileRepository()
    @State private var networkMonitor = KairosNetworkMonitor.shared

    private var preferredScheme: ColorScheme? {
        switch profileRepo.appearanceSettings?.mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
                    .environment(planRepo)
                    .environment(profileRepo)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !networkMonitor.isConnected {
                            OfflineBanner()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(preferredScheme)
        .animation(.easeInOut(duration: 0.25), value: networkMonitor.isConnected)
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated, let uid = Auth.auth().currentUser?.uid else {
                planRepo.stopListening()
                profileRepo.stopListening()
                return
            }
            planRepo.startListening(userID: uid)
            profileRepo.startListening(userID: uid)
        }
    }
}

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text("You're offline")
                    .font(.subheadline.weight(.semibold))
                Text("Changes will sync when you're back online.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're offline. Changes will sync when you're back online.")
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
}
