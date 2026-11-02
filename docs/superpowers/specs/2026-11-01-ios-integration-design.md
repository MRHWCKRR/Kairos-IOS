# iOS integration alignment

Continue the existing SwiftUI app and preserve its UI. The user approved bringing authentication, AI access and data syncing into line with the web app.

Keep Firebase accounts and existing collections. Admit only verified users to the workspace; provide resend, refresh and sign-out on a verification screen. Refresh verification when returning from email. Clear all account-scoped data when the identity changes.

Send Firebase ID and App Check tokens to the Cloudflare AI endpoint. Preserve backend rate limits, verification and attestation checks. Surface backend errors and avoid retrying billable AI requests automatically. Register the native Firebase app as an explicit allowed App Check identity alongside the web identity.

Preserve unknown web fields during iOS planner edits. Use a Firestore transaction and three-way merge against the editor's baseline; reject conflicting changes and preserve unrelated concurrent changes. Fail visibly on undecodable plans. Use the existing study_plans document selection; do not migrate data.

Approach: extend the native app and existing backend. A web wrapper would discard existing native work; a rewrite would unnecessarily replace functioning screens.

Constraints: no billing changes, UI redesign or production deployment. Windows cannot run Xcode. Dependency linking must run with Swift on macOS; Firebase console attestation registration and signed-device testing remain launch prerequisites.
