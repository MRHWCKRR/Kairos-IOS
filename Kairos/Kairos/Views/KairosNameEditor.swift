import SwiftUI

/// The caller owns persistence; the sheet owns its draft until saving succeeds.
struct KairosNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    let heading: String
    let saveLabel: String
    let save: (String) async -> Bool
    let failureMessage: () -> String?
    @State private var draft: String
    @State private var submitting = false
    @State private var error: String?

    init(heading: String, initialValue: String = "", saveLabel: String = "Save",
         failureMessage: @escaping () -> String?, save: @escaping (String) async -> Bool) {
        self.heading = heading
        self.saveLabel = saveLabel
        self.failureMessage = failureMessage
        self.save = save
        _draft = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $draft)
                if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityLabel("Save failed: \(error)") }
                if submitting { ProgressView("Saving…") }
            }
            .disabled(submitting)
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { PlannerSearchButton().disabled(submitting) }
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        guard !submitting else { return }
                        submitting = true
                        error = nil
                        Task {
                            let saved = await save(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                            submitting = false
                            if saved { dismiss() }
                            else { error = failureMessage() ?? "Could not save. Your draft is still here; try again." }
                        }
                    }.disabled(submitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(submitting || !draft.isEmpty)
        }
    }
}
