import SwiftUI

struct OccurrenceDetailsView: View {
    @Environment(StudyPlanRepository.self) private var planRepo
    @Environment(\.dismiss) private var dismiss
    let occurrence: KairosRecurringOccurrence

    // A one-time editor baseline: live snapshots must not replace unsaved steps.
    @State private var items: [KairosChecklistItem]
    @State private var status: String
    @State private var saving = false
    @State private var error: String?

    init(occurrence: KairosRecurringOccurrence) {
        self.occurrence = occurrence
        _items = State(initialValue: occurrence.task.checklist ?? [])
        _status = State(initialValue: occurrence.status)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    details
                    Picker("Status", selection: $status) {
                        Text("Pending").tag("pending")
                        Text("Completed").tag("completed")
                        Text("Skipped").tag("skipped")
                    }.pickerStyle(.segmented)
                    KairosChecklistEditor(items: $items, allowsCompletion: true)
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if saving { ProgressView("Saving…") }
                }
                .padding(20)
                .disabled(saving)
            }
            .kairosBackground()
            .navigationTitle("Occurrence details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(saving || planRepo.isSaving)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(occurrence.task.title).font(.title2.weight(.bold))
            Text("Checklist changes apply only to this occurrence.")
                .font(.subheadline).foregroundStyle(.secondary)
            LabeledContent("Date", value: occurrence.displayDate)
            LabeledContent("Status", value: occurrence.status.capitalized)
            LabeledContent("Time", value: timeLabel)
            if occurrence.occurrenceDate != occurrence.displayDate {
                LabeledContent("Original date", value: occurrence.occurrenceDate)
            }
            if let notes = occurrence.task.notes, !notes.isEmpty {
                Text("Notes").font(.subheadline.weight(.semibold))
                Text(notes).font(.subheadline).textSelection(.enabled)
            }
            if let priority = occurrence.task.priority {
                LabeledContent("Priority", value: priority.capitalized)
            }
            if let minutes = occurrence.task.estimatedMinutes {
                LabeledContent("Estimate", value: "\(minutes) minutes")
            }
        }
        .padding(18).kairosCard(cornerRadius: 22)
    }

    private var timeLabel: String {
        guard let start = occurrence.startTime else { return "Flexible time" }
        if let end = occurrence.endTime { return "\(start)–\(end)" }
        return start
    }

    private func save() {
        guard !saving, !planRepo.isSaving else { return }
        do { try KairosChecklist.validate(items) }
        catch {
            self.error = "Give each step a title of 1–180 characters, with no more than 100 steps."
            return
        }
        guard items != (occurrence.task.checklist ?? []) || status != occurrence.status else { dismiss(); return }
        saving = true
        error = nil
        Task {
            let saved = await planRepo.saveOccurrenceDetails(occurrence, items: items, status: status)
            saving = false
            if saved { dismiss() }
            else { error = planRepo.errorMessage ?? "Could not save. Your checklist edits are still here." }
        }
    }
}
