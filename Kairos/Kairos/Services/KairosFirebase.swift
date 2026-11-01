import FirebaseCore
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

enum KairosFirebase {
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        #if canImport(FirebaseAppCheck)
        #if targetEnvironment(simulator) && DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        #endif
        FirebaseApp.configure()
    }
}
