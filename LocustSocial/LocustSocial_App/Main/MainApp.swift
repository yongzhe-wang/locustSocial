import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()

        let host = "127.0.0.1"
        
        
        //Task { try? await TopicSeeder.seed100ViaAPI(usePicsum: true) }
        
        
        
        // ---- Firestore ----
        let db = Firestore.firestore()
        var settings = db.settings
        settings.isPersistenceEnabled = false   // don’t reuse old prod docs
        settings.isSSLEnabled = false           // ← this is the key line
        settings.host = "\(host):8080"          // emulator port
        db.settings = settings

        // ---- Storage (optional) ----
        let storage = Storage.storage()
        storage.useEmulator(withHost: host, port: 9199)
        
        return true
    }
}


@main
struct LocustSocialApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @State private var isLoggedIn = false
    @State private var isFirebaseReady = false
    @State private var authListener: AuthStateDidChangeListenerHandle?

    var body: some Scene {
        WindowGroup {
            contentView
                .onAppear(perform: setupAutoLogin)
                .onDisappear { detachAuthListener() }
                .onReceive(NotificationCenter.default.publisher(for: .userDidSignOut)) { _ in
                    print("🚪 Received sign-out notification")
                    isLoggedIn = false
                }
        }
    }

    // MARK: - Views
    @ViewBuilder
    private var contentView: some View {
        if !isFirebaseReady {
            ProgressView("Loading…")
        } else if isLoggedIn {
            MainTabView()
                .onAppear { print("✅ MainTabView loaded") }
        } else {
            LoginView(isLoggedIn: $isLoggedIn)
                .onAppear { print("🔵 Showing LoginView") }
        }
    }

    // MARK: - Auto login
    private func setupAutoLogin() {
        // Attach once; Firebase will fire immediately with current user (if any)
        guard authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { _, user in
            isLoggedIn = (user != nil)
            isFirebaseReady = true
            print("🔐 Auth state changed. Logged in:", isLoggedIn)
        }
    }

    private func detachAuthListener() {
        if let authListener {
            Auth.auth().removeStateDidChangeListener(authListener)
            self.authListener = nil
        }
    }
}
