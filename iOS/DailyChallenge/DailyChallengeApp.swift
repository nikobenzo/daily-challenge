import SwiftUI

@main
struct DailyChallengeApp: App {
    @State private var app: PhoneApp = {
        #if DEBUG
        if let fixture = PhoneFixtures.app() { return fixture }
        #endif
        return PhoneApp.production()
    }()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .preferredColorScheme(app.appearance.colorScheme)
        }
        .onChange(of: phase) { _, phase in
            switch phase {
            case .active: app.becameActive()
            case .background: app.enteredBackground()
            default: break
            }
        }
        // Sync and reminder planning while suspended, at times iOS chooses. No other background work.
        .backgroundTask(.appRefresh(PhoneApp.refreshTaskID)) {
            await app.backgroundRefresh()
        }
    }
}
