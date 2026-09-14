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
    private let ambientSounds = ["none", "rain", "forest", "ocean"]

    private var hasUnsavedChanges: Bool {
        mode != savedMode || theme != savedTheme || textColor != savedTextColor ||
        font != savedFont || background != savedBackground || customBackground != savedCustomBackground ||
        ambientSound != savedAmbientSound || Int(ambientVolume.rounded()) != Int(savedAmbientVolume.rounded()) ||
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
            } header: { Text("Appearance") }

            Section("Accent") {
                Picker("Theme", selection: $theme) {
                    Text("Kairos Purple").tag("purple")
                    Text("Ocean Blue").tag("blue")
                    Text("Forest Green").tag("green")
                }
                .pickerStyle(.navigationLink)

                HStack(spacing: 12) {
                    Circle().fill(themeColor.gradient).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kairos accent").font(.subheadline.weight(.semibold))
                        Text("Updates the app tint and visual atmosphere")
                            .font(.caption).foregroundStyle(.secondary)
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
                    fontRow("System", "system")
                    fontRow("Rounded", "rounded")
                    fontRow("Serif", "serif")
                    fontRow("Monospaced", "monospaced")
                }
                .pickerStyle(.navigationLink)

                Text("Aa — The quick brown fox")
                    .font(kairosFont(font).weight(.medium))
                    .padding(.vertical, 4)
            }

            Section("Background") {
                Picker("Style", selection: $background) {
                    Text("Gradient").tag("gradient")
                    Text("Solid").tag("solid")
                    Text("Minimal").tag("minimal")
                }
                .pickerStyle(.navigationLink)

                TextField("Image name or direct image URL (optional)", text: $customBackground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                Text("For bundled images, add the file to Kairos/Resources/Backgrounds and enter its filename without the extension.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Focus") {
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

                    TextField("Direct audio file URL (optional)", text: $customAmbientURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Text("Built-in sounds are loaded from Kairos/Resources/AmbientSounds as rain, forest, or ocean audio files. The custom URL is retained for future remote playback support.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Bundled sounds belong in Kairos/Resources/AmbientSounds. See that folder's documentation for the naming convention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Confetti", isOn: $confetti)
            }

            Section("Accessibility") {
                Toggle("Reduce motion", isOn: $reduceMotion)
                Text("Disables Kairos animated transitions where supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button { Task { await save() } } label: {
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
                Button { attemptLeave() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(isSaving)
            }
        }
        .alert("Unsaved changes", isPresented: $showingUnsavedChanges) {
            Button("Save Changes") { Task { await saveAndLeave() } }
            Button("Discard Changes", role: .destructive) { discardChanges(); dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have changes that haven't been saved. Save them or discard them before leaving Appearance.")
        }
        .task { load() }
    }

    private var themeColor: Color { KairosColors.accent(for: theme) }

    @ViewBuilder
    private func fontRow(_ title: String, _ value: String) -> some View {
        Text(title).font(kairosFont(value)).tag(value)
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
        savedAmbientSound = ambientSound
        savedAmbientVolume = ambientVolume
        savedCustomAmbientURL = customAmbientURL
        savedConfetti = confetti
        savedReduceMotion = reduceMotion
    }

    private func attemptLeave() {
        guard hasUnsavedChanges else { dismiss(); return }
        showingUnsavedChanges = true
    }

    private func discardChanges() {
        mode = savedMode
        theme = savedTheme
        textColor = savedTextColor
        font = savedFont
        background = savedBackground
        customBackground = savedCustomBackground
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
        if didSave { syncSavedValues(); dismiss() }
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
            customBackground: customBackground.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : customBackground.trimmingCharacters(in: .whitespacesAndNewlines),
            cursor: existingAppearance?.cursor ?? "default",
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
        return true
    }
}

#Preview {
    AppearanceSettingsView().environment(UserProfileRepository())
}
