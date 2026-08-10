import SwiftUI

struct DashboardView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            Button("Sign Out") {
                session.signOut()
            }
        }
        .padding(24)
    }
}

#Preview {
    DashboardView()
        .environment(SessionStore())
}
