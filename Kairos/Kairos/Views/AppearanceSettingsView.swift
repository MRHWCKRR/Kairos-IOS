import SwiftUI

struct AppearanceSettingsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.dismiss) private var dismiss

    @State private var mode = "system"
    @State private var theme = "purple"
    @State private var textColor = "default"
    @State private var font = "system"
    @State private var background = "gradient"
    @State private var customBackground = ""
    @State private var cursor = "default"
    @State private var ambientSound = "none"
    @State private var ambientVolume = 50.0
    @State private var customAmbientURL = ""
    @State private var confetti = true
    @State private var reduceMotion = false

    @State private var savedMode = "system"
    @State private var savedTheme = "purple"
    @State private var savedTextColor = "default"
    @State private var savedFont = "system"
    @State private var savedBackground = "gradient"
    @State private var savedCustomBackground = ""
    @State private var savedCursor = "default"
    @State private var savedAmbientSound = "none"
    @State private var savedAmbientVolume = 50.0
    @State private var savedCustomAmbientURL = ""
    @State private var savedConfetti = true
    @State private var savedReduceMotion = false

    @State private var isSaving = false
    @State private var showingUnsavedChanges = false

    private let modes = ["system", "light", "dark"]
    private let themes = ["purple", "blue", "green"]
    private let textColors = ["default", "white", "black"]
    private let fonts = ["system", "rounded", "serif", "monospaced"]
    private let backgrounds = ["gradient", "solid", "minimal"]
    private let cursors = ["default", "line", "block"]
    private let ambientSounds = ["none", "rain", "forest", "ocean"]

    private var hasUnsavedChanges: Bool {
        mode != savedMode || theme != savedTheme || textColor != savedTextColor ||
        font != savedFont || background != savedBackground || customBackground != savedCustomBackground ||
        cursor != savedCursor || ambientSound != savedAmbientSound ||
        Int(ambientVolume.rounded()) != Int(savedAmbientVolume.rounded()) ||
        customAmbientURL != savedCustomAmbientURL || confetti != savedConfetti ||
        reduceMotion != savedReduceMotion
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

            Section("Typography") {
                Picker("Text color", selection: $textColor) {
                    Text("Default").tag("default")
                    Text("White").tag("white")
                    Text("Black").tag("black")
                }
                .pickerStyle(.navigationLink)

                Picker("Font", selection: $font) {
                    Text("System").tag("system")
                    Text("Rounded").tag("rounded")
                    Text("Serif").tag("serif")
                    Text("Monospaced").tag("monospaced")
                }
                .pickerStyle(.navigationLink)
            }

            Section("Background") {
                Picker("Style", selection: $background) {
                    Text("Gradient").tag("gradient")
                    Text("Solid").tag("solid")
                    Text("Minimal").tag("minimal")
                }
                .pickerStyle(.navigationLink)

                if background == "solid" {
                    TextField("Custom background URL (optional)", text: $customBackground)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }

            Section("Focus") {
                Picker("Cursor", selection: $cursor) {
                    Text("Default").tag("default")
                    Text("Line").tag("line")
                    Text("Block").tag("block")
                }
                .pickerStyle(.navigationLink)

                Picker("Ambient sound", selection: $ambientSound) {
                    Text("None").tag("none")
                    Text("Rain").tag("rain")
                    Text("Forest").tag("forest")
                    Text("Ocean").tag("ocean")
                }
                .pickerStyle(.navigationLink)

                if ambientSound != "none" {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text("\(Int(ambientVolume.rounded()))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $ambientVolume, in: 0...100, step: 1)
                    }

                    TextField("Custom YouTube URL (optional)", text: $customAmbientURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Toggle("Confetti", isOn: $confetti)
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
            textColor = textColors.contains(settings.textColor) ? settings.textColor : "default"
            font = fonts.contains(settings.font) ? settings.font : "system"
            background = backgrounds.contains(settings.background) ? settings.background : "gradient"
            customBackground = settings.customBackground ?? ""
            cursor = cursors.contains(settings.cursor) ? settings.cursor : "default"
            ambientSound = ambientSounds.contains(settings.ambientSound) ? settings.ambientSound : "none"
            ambientVolume = min(max(Double(settings.ambientVolume), 0), 100)
            customAmbientURL = settings.customAmbientYoutubeUrl
            confetti = settings.confetti
        }
        reduceMotion = profileRepo.accessibilitySettings?.reduceMotion ?? false
        syncSavedValues()
    }

    private func syncSavedValues() {
        savedMode = mode
        savedTheme = theme
        savedTextColor = textColor
        savedFont = font
        savedBackground = background
        savedCustomBackground = customBackground
        savedCursor = cursor
        savedAmbientSound = ambientSound
        savedAmbientVolume = ambientVolume
        savedCustomAmbientURL = customAmbientURL
        savedConfetti = confetti
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
        textColor = savedTextColor
        font = savedFont
        background = savedBackground
        customBackground = savedCustomBackground
        cursor = savedCursor
        ambientSound = savedAmbientSound
        ambientVolume = savedAmbientVolume
        customAmbientURL = savedCustomAmbientURL
        confetti = savedConfetti
        reduceMotion = savedReduceMotion
    }

    private func save() async {
        isSaving = true
        let didSave = await persistDraft()
        isSaving = false
        if didSave { syncSavedValues() }
    }

    private func saveAndLeave() async {
        isSaving = true
        let didSave = await persistDraft()
        isSaving = false
        if didSave {
            syncSavedValues()
            dismiss()
        }
    }

    @discardableResult
    private func persistDraft() async -> Bool {
        let existingAppearance = profileRepo.appearanceSettings
        let appearance = KairosAppearanceSettings(
            mode: mode,
            theme: theme,
            textColor: textColor,
            font: font,
            background: background,
            customBackground: customBackground.isEmpty ? nil : customBackground,
            cursor: cursor,
            ambientSound: ambientSound,
            ambientVolume: Int(ambientVolume.rounded()),
            customAmbientYoutubeUrl: customAmbientURL,
            confetti: confetti
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
            profileRepo.appearanceSettings = originalAppearance
            profileRepo.accessibilitySettings = originalAccessibility
            return false
        }

        // Keep the UI stable when a custom URL is cleared while a built-in
        // background/sound is selected: the persisted field remains empty.
        _ = existingAppearance
        return true
    }
}

#Preview {
    AppearanceSettingsView()
        .environment(UserProfileRepository())
}
