import Foundation
import ServiceManagement

@main
struct LoginItemFixture {
    @MainActor static func main() {
        guard Bundle.main.bundleIdentifier == "app.daily-challenge.login-fixture" else {
            fatalError("Refusing to register a non-fixture bundle")
        }
        let service = MainAppLoginItemService()
        print("Before: \(service.status.rawValue)")
        do {
            try service.register()
            print("After register: \(service.status.rawValue)")
        } catch {
            print("Registration failed: \(error)")
        }
        // Also clean up when registration throws after partially changing OS state.
        do {
            try service.unregister()
            print("After unregister: \(service.status.rawValue)")
        } catch {
            print("Cleanup failed: \(error)")
            exit(1)
        }
        guard service.status == .notRegistered || service.status == .notFound else {
            print("Fixture is still registered; cleanup requires attention")
            exit(1)
        }
    }
}
