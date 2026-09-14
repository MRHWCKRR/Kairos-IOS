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
                Text("Changes stay pending until you tap Save appearance.")
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
        // Draft values never modify the shared profile, so discarding simply
        // restores the controls to their last saved values before leaving.
        mode = savedMode
        theme = savedTheme
        reduceMotion = savedReduceMotion
    }

    private func save() async {
        isSaving = true
        let didSave = await persistDraft()
        isSaving = false
        if didSave {
            // The shared profile is updated by the repository only after the
            // Firestore write succeeds, so one Save commits both persistence
            // and the app-wide appearance.
            savedMode = mode
            savedTheme = theme
            savedReduceMotion = reduceMotion
        }
    }

    private func saveAndLeave() async {
        isSaving = true
        let didSave = await persistDraft()
        isSaving = false
        if didSave {
            savedMode = mode
            savedTheme = theme
            savedReduceMotion = reduceMotion
            dismiss()
        }
    }

    @discardableResult
    private func persistDraft() async -> Bool {
        // Build the appearance from the draft controls without mutating the
        // shared repository first. The app therefore stays on the currently
        // saved theme until the user explicitly commits the change.
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

        let originalAppearance = profileRepo.appearanceSettings
        let originalAccessibility = profileRepo.accessibilitySettings

        await profileRepo.saveAppearanceSettings(appearance)
        guard profileRepo.appearanceSettings == appearance else { return false }

        await profileRepo.saveAccessibilitySettings(accessibility)
        guard profileRepo.accessibilitySettings == accessibility else {
            // If the second write fails, restore the previously committed
            // in-memory appearance so the UI doesn't claim both settings saved.
            profileRepo.appearanceSettings = originalAppearance
            profileRepo.accessibilitySettings = originalAccessibility
            return false
        }

        return true
    }
}

#Preview {
    AppearanceSettingsView()
        .environment(UserProfileRepository())
}
