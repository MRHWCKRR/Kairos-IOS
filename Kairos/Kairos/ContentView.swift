import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @Environment(SessionStore.self) private var session
    @State private var planRepo = StudyPlanRepository()
    @State private var profileRepo = UserProfileRepository()

    var body: some View {
        Group {
            if session.isAuthenticated {
                MainTabView()
                    .environment(planRepo)
                    .environment(profileRepo)
            } else {
                LoginView()
            }
        }
        .task(id: session.isAuthenticated) {
            guard session.isAuthenticated, let uid = Auth.auth().currentUser?.uid else {
                planRepo.stopListening()
                profileRepo.stopListening()
                return
            }
            planRepo.startListening(userID: uid)
            profileRepo.startListening(userID: uid)
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
}
