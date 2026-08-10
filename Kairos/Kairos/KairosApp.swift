//
//  KairosApp.swift
//  Kairos
//
//  Created by Yunfei Na on 10/8/2026.
//

import SwiftUI

@main
struct KairosApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
        }
    }
}
