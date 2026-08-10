//
//  ContentView.swift
//  Kairos
//
//  Created by Yunfei Na on 10/8/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.isAuthenticated {
                DashboardView()
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(SessionStore())
}
