import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @State private var mode = "system"
    @State private var theme = "purple"
    @State private var reduceMotion = false
    @State private var isSaving = false

    private let modes = ["system", "light", "dark"]
    private let themes = ["purple", "blue", "green"]

    var body: some View {
        List {
            Section {
                Picker("Appearance", selection: $mode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your iPhone's Light or Dark Mode setting.")
            }

            Section("Accent") {
                Picker("Theme", selection: $theme) {
                    Text("Kairos Purple").tag("purple")
                    Text("Ocean Blue").tag("blue")
                    Text("Forest Green").tag("green")
                }
                .pickerStyle(.navigationLink)

                HStack(spacing: 12) {
                    Circle()
                        .fill(themeColor.gradient)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kairos accent")
                            .font(.subheadline.weight(.semibold))
                        Text("Used for primary actions and progress")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Accessibility") {
                Toggle("Reduce motion", isOn: $reduceMotion)
                Text("Reduce animated transitions and other motion where supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(isSaving ? "Saving…" : "Save appearance")
                        Spacer()
                        if isSaving { ProgressView() }
                    }
                }
                .disabled(isSaving)
            }
        }
        .scrollContentBackground(.hidden)
        .kairosBackground()
        .navigationTitle("Appearance")
        .task { load() }
    }

    private var themeColor: Color {
        switch theme {
        case "blue": return Color(red: 0.20, green: 0.45, blue: 0.95)
        case "green": return Color(red: 0.18, green: 0.62, blue: 0.40)
        default: return KairosColors.accent
        }
    }

    private func load() {
        if let settings = profileRepo.appearanceSettings {
            mode = modes.contains(settings.mode) ? settings.mode : "system"
            theme = themes.contains(settings.theme) ? settings.theme : "purple"
        }
        reduceMotion = profileRepo.accessibilitySettings?.reduceMotion ?? false
    }

    private func save() async {
        isSaving = true

        let existingAppearance = profileRepo.appearanceSettings
        let appearance = KairosAppearanceSettings(
            mode: mode,
            theme: theme,
            textColor: existingAppearance?.textColor ?? "default",
            font: existingAppearance?.font ?? "system",
            background: existingAppearance?.background ?? "gradient",
            customBackground: existingAppearance?.customBackground,
            cursor: existingAppearance?.cursor ?? "default",
            ambientSound: existingAppearance?.ambientSound ?? "none",
            ambientVolume: existingAppearance?.ambientVolume ?? 50,
            customAmbientYoutubeUrl: existingAppearance?.customAmbientYoutubeUrl ?? "",
            confetti: existingAppearance?.confetti ?? true
        )

        let existingAccessibility = profileRepo.accessibilitySettings
        let accessibility = KairosAccessibilitySettings(
            density: existingAccessibility?.density ?? "comfortable",
            timeFormat: existingAccessibility?.timeFormat ?? "24h",
            reduceMotion: reduceMotion,
            language: existingAccessibility?.language ?? "en"
        )

        await profileRepo.saveAppearanceSettings(appearance)
        await profileRepo.saveAccessibilitySettings(accessibility)
        isSaving = false
    }
}

#Preview {
    AppearanceSettingsView()
        .environment(UserProfileRepository())
}
