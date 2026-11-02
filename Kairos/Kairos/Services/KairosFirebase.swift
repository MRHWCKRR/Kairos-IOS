import FirebaseCore
import FirebaseAppCheck

enum KairosFirebase {
    static func configure() {
        guard FirebaseApp.app() == nil else { return }
        #if targetEnvironment(simulator) && DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        FirebaseApp.configure()
    }
}
