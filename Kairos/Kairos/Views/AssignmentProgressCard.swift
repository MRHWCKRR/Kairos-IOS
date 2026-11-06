import SwiftUI

struct AssignmentProgressCard: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(UserProfileRepository.self) private var profileRepo
    let taskID: String
    let open: (String) -> Void
    @State private var summary: KairosAssignmentSummary?
    @State private var loadedKey = ""
    @State private var error: String?
    private var timezone: TimeZone { profileRepo.profile.flatMap { TimeZone(identifier: $0.timezone) } ?? .current }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tick in
            let today = KairosDate.dayKey(for: tick.date, timeZone: timezone)
            let key = "\(planRepo.searchScope ?? "")-\(planRepo.plannerRevision)-\(today)-\(taskID)"
            Group {
                if loadedKey == key, let summary { card(summary) }
                else if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }.task(id: key) { await load(key: key, today: today) }
        }
    }
    private func load(key: String, today: String) async {
        error = nil
        do {
            let result = try await planRepo.assignmentProgress(taskID: taskID, today: today)
            try Task.checkCancellation(); summary = result; loadedKey = key
        } catch is CancellationError { }
        catch { guard !Task.isCancelled else { return }; self.error = "Assignment progress could not load. Your task draft is unchanged." }
    }
    private func card(_ value: KairosAssignmentSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(value.isSession == true ? "Assignment session" : "Assignment progress", sharedIcon: "list.bullet.clipboard").font(.headline)
            if value.isSession == true {
                Button(value.parentTitle) { open(value.parentId) }.font(.subheadline.weight(.semibold))
                if let number = value.sessionIndex { Text("Session \(number)").font(.caption).foregroundStyle(.secondary) }
            }
            Text("\(value.completed) of \(value.total) sessions complete · \(value.remainingMinutes) min remaining estimate").font(.subheadline)
            ProgressView(value: Double(value.completed), total: Double(max(1, value.total))).tint(KairosColors.accent)
            Text(value.status + (value.lateSessions > 0 ? " · \(value.lateSessions) scheduled after the deadline" : "")).font(.caption).foregroundStyle(.secondary)
            if value.ordered {
                Text(value.isSession == true ? readiness(value.readiness) : "Ordered sessions · \(value.readyCount) ready · \(value.waitingCount) waiting").font(.caption)
            }
            if value.orderNeedsReview { Text("Session order needs rescheduling. Review the session plan on the web.").font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Linked sessions (\(value.total))") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(value.sessions) { session in
                        Button { open(session.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title).font(.subheadline).foregroundStyle(.primary).strikethrough(session.completed)
                                Text(sessionText(session)).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    if value.ordered { Text("Ready means earlier active sessions are complete. Scheduled times are unchanged.").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.padding(18).kairosCard(cornerRadius: 22)
    }
    private func readiness(_ value: KairosSessionReadiness?) -> String {
        guard let value else { return "" }
        switch value.state {
        case "ready": return "Ready"
        case "waiting": return "Waiting for " + (value.waitingTitle ?? "an earlier session")
        case "review": return "Review session order"
        default: return "Completed"
        }
    }
    private func sessionText(_ session: KairosAssignmentSession) -> String {
        var parts = [session.completed ? "Completed" : session.date ?? "Unscheduled", "\(session.minutes) min"]
        if !session.completed, let time = session.startTime { parts.append(KairosTimeDisplay.time(time, format: profileRepo.accessibilitySettings?.timeFormat ?? "12")) }
        if !session.completed, let status = session.readiness { parts.append(readiness(status)) }
        return parts.joined(separator: " · ")
    }
}

