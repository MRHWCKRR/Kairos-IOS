# iOS integration setup and release checks

This extends the existing native app; no Firestore migration is needed. Accounts and AI allowances are shared with Kairos web. The Cloudflare companion change is https://github.com/MRHWCKRR/Kairos/pull/146.

## Mac setup

Open `Kairos/Kairos.xcodeproj` with Xcode supporting the project's existing iOS 26.5 minimum. FirebaseAppCheck is already linked, `-ObjC` is set, and `Kairos.entitlements` selects the production App Attest environment. These project changes were generated using the Firebase skill's Swift/XcodeProj tool on macOS; the existing Firebase package requirement is retained. No extra setup script is required.

Do not put an AI provider key in the app. The empty legacy `Config.xcconfig` satisfies an existing resource reference.

## Firebase and signing

1. In Firebase project `kairos-1a`, register App Attest for iOS app `1:63554361:ios:fb19651206b6c5e1411ee8`, bundle `com.bytebybyte.kairos`.
2. Enable App Attest for the app's Apple identifier/signing profile. The entitlement uses the production environment required for Firebase App Check.
3. For simulator Debug builds, register the debug token printed by the Firebase SDK in Firebase Console → App Check. Never commit a debug token. Device builds use App Attest, including Debug builds on physical devices.
4. Merge and deploy the companion backend PR before testing native AI against production. The backend accepts only the configured web identity and this exact native identity, after JWT verification.

## Verification

`swift test` exercises the Foundation-only access, AI contract, merge and progress helpers. The macOS CI workflow additionally builds the real Xcode project for the arm64 simulator without signing. This does not replace signed-device testing.

Before release, exercise: email sign-up → verification email → resend cooldown → return to app; verified email and Google sign-in; sign-out/account switch with a pending AI request and running focus timer; normal AI response, offline request, App Check failure and shared daily/weekly allowance errors; edit/delete a task carrying web-only fields; simultaneous web/native edits to different fields and the same field; focus and completion accounting on two devices; and persistence after relaunch.

Planner transactions require connectivity. An offline save surfaces an error rather than promising that a transaction was queued. A malformed newest plan surfaces an update-required error instead of silently selecting an older plan. AI requests are not automatically retried, because attempts count toward backend allowances.

Reference: https://firebase.google.com/docs/app-check/ios/app-attest-provider and https://firebase.google.com/docs/app-check/ios/custom-resource.

## Existing build warnings

The unsigned simulator build succeeds. It still reports existing warnings for deprecated Text concatenation in LoginView, a Swift 6 concurrency capture in KairosNotificationManager, and unused animation/task results in DashboardView. The widget uses the canonical bundle metadata keys; CI validates its built package type and version agreement with the containing app before distribution.
