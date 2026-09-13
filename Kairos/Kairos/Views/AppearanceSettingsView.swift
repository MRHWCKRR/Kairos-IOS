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
                        .fill(KairosColors.accent.gradient)
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

    private func load() {
        guard let settings = profileRepo.appearanceSettings else { return }
        mode = settings.mode.isEmpty ? "system" : settings.mode
        theme = settings.theme.isEmpty ? "purple" : settings.theme
    }

    private func save() async {
        isSaving = true
        let existing = profileRepo.appearanceSettings
        let settings = KairosAppearanceSettings(
            mode: mode,
            theme: theme,
            textColor: existing?.textColor ?? "default",
            font: existing?.font ?? "system",
            background: existing?.background ?? "gradient",
            customBackground: existing?.customBackground,
            cursor: existing?.cursor ?? "default",
            ambientSound: existing?.ambientSound ?? "none",
            ambientVolume: existing?.ambientVolume ?? 50,
            customAmbientYoutubeUrl: existing?.customAmbientYoutubeUrl ?? "",
            confetti: existing?.confetti ?? true
        )
        await profileRepo.saveAppearanceSettings(settings)
        isSaving = false
    }
}

#Preview {
    AppearanceSettingsView()
        .environment(UserProfileRepository())
}
