import Foundation
import Observation
import FirebaseFirestore

@Observable
@MainActor
final class StudyPlanRepository {
    var currentPlan: KairosStudyPlan?
    var isLoading = false
    var errorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    /// Mirrors the web app's `loadLatestPlanFromFirestore`: query all plans for
    /// this user, sort by createdAt client-side (no orderBy, avoids needing a
    /// composite index), and use a real-time listener so it stays live.
    func startListening(userID: String) {
        stopListening()
        isLoading = true

        listener = db.collection("study_plans")
            .whereField("userID", isEqualTo: userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let documents = snapshot?.documents, !documents.isEmpty else {
                    self.currentPlan = nil
                    return
                }

                let plans = documents.compactMap { try? $0.data(as: KairosStudyPlan.self) }
                self.currentPlan = plans.max { lhs, rhs in
                    (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
                }
                self.errorMessage = nil
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }

    /// Matches the web app's `updatePlanInFirestore`: patch only the `boards`
    /// field via updateDoc, not a full-document overwrite.
    func toggleTask(boardID: String, sectionID: String, taskID: String) async {
        guard var plan = currentPlan, let planID = plan.id else { return }

        guard let boardIndex = plan.boards.firstIndex(where: { $0.id == boardID }),
              let sectionIndex = plan.boards[boardIndex].sections.firstIndex(where: { $0.id == sectionID }),
              let taskIndex = plan.boards[boardIndex].sections[sectionIndex].tasks.firstIndex(where: { $0.id == taskID }) else {
            return
        }

        plan.boards[boardIndex].sections[sectionIndex].tasks[taskIndex].completed.toggle()

        do {
            let encoder = Firestore.Encoder()
            let encodedBoards = try plan.boards.map { try encoder.encode($0) }
            try await db.collection("study_plans").document(planID).updateData(["boards": encodedBoards])
            // currentPlan updates automatically via the snapshot listener.
        } catch {
            errorMessage = "Failed to update task: \(error.localizedDescription)"
        }
    }
}
