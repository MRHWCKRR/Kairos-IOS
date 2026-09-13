//
//  KairosApp.swift
//  Kairos
//
//  Created by Yunfei Na on 10/8/2026.
//

import SwiftUI
import FirebaseCore
import GoogleSignIn
import UserNotifications

@main
struct KairosApp: App {
    @State private var session = SessionStore()
    private let notificationDelegate = KairosNotificationDelegate()

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
