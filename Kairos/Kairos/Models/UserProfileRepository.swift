import Foundation
import Observation
import FirebaseFirestore

@Observable
@MainActor
final class UserProfileRepository {
    var profile: KairosUserProfile?
    var isLoading = false
    var errorMessage: String?

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    func startListening(userID: String) {
        stopListening()
        isLoading = true

        listener = db.collection("users").document(userID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = try? snapshot?.data(as: KairosUserDocument.self) else {
                    self.profile = nil
                    return
                }

                self.profile = data.settings?.profile
                self.errorMessage = nil
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}
