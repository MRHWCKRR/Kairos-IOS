import SwiftUI

struct NotificationSettingsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @State private var notificationManager = KairosNotificationManager()
    @State private var showingPermissionAlert = false

    private var settings: KairosNotificationSettings {
        profileRepo.notificationSettings ?? KairosNotificationSettings(
            enabled: true,
            boardCompletion: true,
            bedtimeReminders: true,
            browserPush: true
        )
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                introCard
                permissionCard
                preferencesCard
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .kairosBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Notifications are off", isPresented: $showingPermissionAlert) {
            Button("Open Settings") { notificationManager.openSystemSettings() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Allow Kairos notifications in iOS Settings to receive local reminders.")
        }
        .onAppear { notificationManager.refreshAuthorizationState() }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.title2)
                .foregroundStyle(KairosColors.accent)
            Text("Stay in rhythm")
                .font(.title3.weight(.bold))
            Text("Choose which moments Kairos can surface without interrupting your focus.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .kairosCard(cornerRadius: 24)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("iOS permission", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            if notificationManager.authorizationState == .notDetermined {
                Button {
                    Task {
                        let granted = await notificationManager.requestAuthorization()
                        if !granted { showingPermissionAlert = true }
                    }
                } label: {
                    Label("Allow Notifications", systemImage: "bell.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(KairosColors.accent)
            } else if notificationManager.authorizationState == .denied {
                Button("Open iOS Settings", systemImage: "gear") {
                    notificationManager.openSystemSettings()
                }
                .buttonStyle(.glass)
            }
        }
        .padding(18)
        .kairosCard(cornerRadius: 24)
    }

    private var statusBadge: some View {
        Text(permissionLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var permissionLabel: String {
        switch notificationManager.authorizationState {
        case .notDetermined: return "Not set"
        case .denied: return "Off"
        case .authorized, .provisional, .ephemeral: return "On"
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Kairos preferences")
                .font(.headline)
                .padding(.bottom, 4)

            settingRow(
                title: "Notifications",
                subtitle: "Allow Kairos to surface local updates.",
                keyPath: \KairosNotificationSettings.enabled
            )
            settingRow(
                title: "Board completion",
                subtitle: "Celebrate when every task on a board is complete.",
                keyPath: \KairosNotificationSettings.boardCompletion
            )
            settingRow(
                title: "Bedtime reminders",
                subtitle: "Keep the existing cross-platform preference ready for scheduling.",
                keyPath: \KairosNotificationSettings.bedtimeReminders
            )
            settingRow(
                title: "Browser push",
                subtitle: "Preserve the shared account preference for web notifications.",
                keyPath: \KairosNotificationSettings.browserPush
            )
        }
        .padding(18)
        .kairosCard(cornerRadius: 24)
    }

    private func settingRow(
        title: String,
        subtitle: String,
        keyPath: WritableKeyPath<KairosNotificationSettings, Bool>
    ) -> some View {
        let isOn = Binding<Bool>(
            get: { settings[keyPath: keyPath] },
            set: { newValue in
                Task { await saveSetting(keyPath: keyPath, value: newValue) }
            }
        )

        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(KairosColors.accent)
        .padding(.vertical, 8)
    }

    private func saveSetting(
        keyPath: WritableKeyPath<KairosNotificationSettings, Bool>,
        value: Bool
    ) async {
        var updated = settings
        updated[keyPath: keyPath] = value
        profileRepo.notificationSettings = updated
        await profileRepo.saveNotificationSettings(updated)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environment(UserProfileRepository())
    }
}
