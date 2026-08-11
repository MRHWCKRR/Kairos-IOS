//
//  KairosApp.swift
//  Kairos
//
//  Created by Yunfei Na on 10/8/2026.
//

import SwiftUI
import GoogleSignIn

@main
struct KairosApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
