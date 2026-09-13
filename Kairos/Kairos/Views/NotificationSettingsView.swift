import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @Environment(UserProfileRepository.self) private var profileRepo
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationManager = KairosNotificationManager()
    @State private var reminderManager = KairosReminderManager()
    @State private var showingPermissionAlert = false
    @State private var showingReminderAlert = false

    private var settings: KairosNotificationSettings {
        profileRepo.notificationSettings ?? KairosNotificationSettings(
            enabled: true,
            boardCompletion: true,
            bedtimeReminders: true,
            browserPush: true
        )
    }

    private var bedtimeScheduleID: String {
        "\(settings.enabled)-\(settings.bedtimeReminders)-\(notificationManager.authorizationState)"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                introCard
                permissionCard
                remindersCard
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
        .alert("Reminders access", isPresented: $showingReminderAlert) {
            Button("Open Settings") { openSystemSettings() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Allow Kairos access to Reminders in iOS Settings before exporting study tasks.")
        }
        .onAppear { refreshPermissions() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissions()
        }
        .task(id: bedtimeScheduleID) {
            await KairosBedtimeReminderScheduler.refresh(
                enabled: settings.bedtimeReminders,
                notificationsEnabled: settings.enabled && notificationManager.authorizationState != .denied
            )
        }
    }

    private func refreshPermissions() {
        notificationManager.refreshAuthorizationState()
        reminderManager.refreshAuthorizationState()
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

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Apple Reminders", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text(reminderPermissionLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text("Connect Kairos to Reminders so study tasks can become native iOS reminders with their planned date.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if reminderManager.authorizationState == .notDetermined {
                Button {
                    Task {
                        let granted = await reminderManager.requestAccess()
                        if !granted { showingReminderAlert = true }
                    }
                } label: {
                    Label("Allow Reminders Access", systemImage: "checklist")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(KairosColors.accent)
            } else if reminderManager.authorizationState == .denied {
                Button("Open iOS Settings", systemImage: "gear") {
                    openSystemSettings()
                }
                .buttonStyle(.glass)
            } else if reminderManager.authorizationState == .authorized {
                Label("Ready for task export", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            } else {
                Label("Reminders access is restricted", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(18)
        .kairosCard(cornerRadius: 24)
    }

    private var reminderPermissionLabel: String {
        switch reminderManager.authorizationState {
        case .notDetermined: return "Not set"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        case .authorized: return "On"
        }
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

            settingRow(title: "Notifications", subtitle: "Allow Kairos to surface local updates.", keyPath: \.enabled)
            settingRow(title: "Board completion", subtitle: "Celebrate when every task on a board is complete.", keyPath: \.boardCompletion)
            settingRow(title: "Bedtime reminders", subtitle: "Get a gentle 9:00 PM local reminder to wind down.", keyPath: \.bedtimeReminders)
            settingRow(title: "Browser push", subtitle: "Preserve the shared account preference for web notifications.", keyPath: \.browserPush)
        }
        .padding(18)
        .kairosCard(cornerRadius: 24)
    }

    private func settingRow(title: String, subtitle: String, keyPath: WritableKeyPath<KairosNotificationSettings, Bool>) -> some View {
        let isOn = Binding<Bool>(
            get: { settings[keyPath: keyPath] },
            set: { newValue in Task { await saveSetting(keyPath: keyPath, value: newValue) } }
        )
        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(KairosColors.accent)
        .padding(.vertical, 8)
    }

    private func saveSetting(keyPath: WritableKeyPath<KairosNotificationSettings, Bool>, value: Bool) async {
        var updated = settings
        updated[keyPath: keyPath] = value
        profileRepo.notificationSettings = updated
        await profileRepo.saveNotificationSettings(updated)
        await KairosBedtimeReminderScheduler.refresh(
            enabled: updated.bedtimeReminders,
            notificationsEnabled: updated.enabled && notificationManager.authorizationState != .denied
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environment(UserProfileRepository())
    }
}
