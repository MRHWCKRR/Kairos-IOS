import SwiftUI
import FirebaseAuth
import AVFoundation

struct ContentView: View {
    @Environment(SessionStore.self) private var session
    @State private var planRepo = StudyPlanRepository()
    @State private var profileRepo = UserProfileRepository()
    @State private var networkMonitor = KairosNetworkMonitor.shared
    @State private var ambientAudio = KairosAmbientAudioController()

    private var preferredScheme: ColorScheme? {
        switch profileRepo.appearanceSettings?.mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var appearance: KairosAppearanceSettings? { profileRepo.appearanceSettings }
    private var accentColor: Color { KairosColors.accent(for: appearance?.theme) }
    private var reduceMotion: Bool { profileRepo.accessibilitySettings?.reduceMotion ?? false }

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
                    .environment(planRepo)
                    .environment(profileRepo)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if !networkMonitor.isConnected {
                            OfflineBanner()
                                .transition(
                                    reduceMotion
                                    ? .opacity
                                    : .move(edge: .top).combined(with: .opacity)
                                )
                        }
                    }
            } else {
                LoginView()
            }
        }
        .preferredColorScheme(preferredScheme)
        .tint(accentColor)
        .font(kairosFont(appearance?.font))
        .foregroundStyle(kairosTextColor(appearance?.textColor))
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.25),
            value: networkMonitor.isConnected
        )
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated, let uid = Auth.auth().currentUser?.uid else {
                planRepo.stopListening()
                profileRepo.stopListening()
                ambientAudio.stop()
                return
            }
            planRepo.startListening(userID: uid)
            profileRepo.startListening(userID: uid)
        }
        .task(id: ambientAudioKey) {
            await ambientAudio.apply(appearance)
        }
    }

    private var ambientAudioKey: String {
        guard let appearance else { return "none" }
        return "\(appearance.ambientSound)-\(appearance.ambientVolume)-\(appearance.customAmbientYoutubeUrl)"
    }
}

@MainActor
final class KairosAmbientAudioController {
    private var player: AVAudioPlayer?

    func apply(_ settings: KairosAppearanceSettings?) async {
        stop()
        guard let settings, settings.ambientSound != "none", settings.ambientVolume > 0 else { return }

        let candidates = [
            settings.ambientSound,
            settings.ambientSound.lowercased()
        ]
        let url = candidates.lazy.compactMap { name in
            Bundle.main.url(forResource: name, withExtension: "mp3")
                ?? Bundle.main.url(forResource: name, withExtension: "m4a")
                ?? Bundle.main.url(forResource: name, withExtension: "wav")
        }.first

        guard let url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.numberOfLoops = -1
            audioPlayer.volume = Float(settings.ambientVolume) / 100
            audioPlayer.prepareToPlay()
            audioPlayer.play()
            player = audioPlayer
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
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
                Text("Changes may sync when you're back online.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're offline. Changes may sync when you're back online.")
    }
}

#Preview {
    ContentView().environment(SessionStore())
}
