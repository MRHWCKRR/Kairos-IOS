import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss

    @State private var mode = "system"
    @State private var theme = "purple"
    @State private var reduceMotion = false

    @State private var savedMode = "system"
    @State private var savedTheme = "purple"
    @State private var savedReduceMotion = false

    @State private var isSaving = false
    @State private var showingUnsavedChanges = false

    private let modes = ["system", "light", "dark"]
    private let themes = ["purple", "blue", "green"]

    private var hasUnsavedChanges: Bool {
        mode != savedMode || theme != savedTheme || reduceMotion != savedReduceMotion
    }

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
                Text("Changes are previewed immediately and saved only when you tap Save appearance.")
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
                .disabled(isSaving || !hasUnsavedChanges)
            }
        }
        .scrollContentBackground(.hidden)
        .kairosBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    attemptLeave()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .disabled(isSaving)
            }
        }
        .alert("Unsaved changes", isPresented: $showingUnsavedChanges) {
            Button("Save Changes") {
                Task { await saveAndLeave() }
            }
            Button("Discard Changes", role: .destructive) {
                discardChanges()
                dismiss()
            }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have changes that haven't been saved. Save them or discard them before leaving Appearance.")
        }
        .onChange(of: mode) { _, _ in applyPreview() }
        .onChange(of: theme) { _, _ in applyPreview() }
        .onChange(of: reduceMotion) { _, _ in applyPreview() }
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
        guard !hasUnsavedChanges else { return }
        if let settings = profileRepo.appearanceSettings {
            mode = modes.contains(settings.mode) ? settings.mode : "system"
            theme = themes.contains(settings.theme) ? settings.theme : "purple"
        }
        reduceMotion = profileRepo.accessibilitySettings?.reduceMotion ?? false
        savedMode = mode
        savedTheme = theme
        savedReduceMotion = reduceMotion
    }

    private func attemptLeave() {
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        showingUnsavedChanges = true
    }

    private func discardChanges() {
        mode = savedMode
        theme = savedTheme
        reduceMotion = savedReduceMotion
        restoreSavedPreview()
    }

    private func save() async {
        isSaving = true
        await persistDraft()
        isSaving = false
    }

    private func saveAndLeave() async {
        isSaving = true
        let didSave = await persistDraft()
        isSaving = false
        if didSave {
            dismiss()
        }
    }

    // Apply the draft to the shared in-memory settings so ContentView previews
    // mode/theme changes immediately. Nothing is written to Firestore here.
    private func applyPreview() {
        guard hasUnsavedChanges else { return }
        let existingAppearance = profileRepo.appearanceSettings
        profileRepo.appearanceSettings = KairosAppearanceSettings(
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
        profileRepo.accessibilitySettings = KairosAccessibilitySettings(
            density: existingAccessibility?.density ?? "comfortable",
            timeFormat: existingAccessibility?.timeFormat ?? "24h",
            reduceMotion: reduceMotion,
            language: existingAccessibility?.language ?? "en"
        )
    }

    private func restoreSavedPreview() {
        let existingAppearance = profileRepo.appearanceSettings
        profileRepo.appearanceSettings = KairosAppearanceSettings(
            mode: savedMode,
            theme: savedTheme,
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
        profileRepo.accessibilitySettings = KairosAccessibilitySettings(
            density: existingAccessibility?.density ?? "comfortable",
            timeFormat: existingAccessibility?.timeFormat ?? "24h",
            reduceMotion: savedReduceMotion,
            language: existingAccessibility?.language ?? "en"
        )
    }

    @discardableResult
    private func persistDraft() async -> Bool {
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

        let appearanceSaved = profileRepo.appearanceSettings == appearance
        let accessibilitySaved = profileRepo.accessibilitySettings == accessibility
        guard appearanceSaved && accessibilitySaved else { return false }

        savedMode = mode
        savedTheme = theme
        savedReduceMotion = reduceMotion
        return true
    }
}

#Preview {
    AppearanceSettingsView()
        .environment(UserProfileRepository())
}
