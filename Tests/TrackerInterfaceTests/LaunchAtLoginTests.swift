import Foundation
import ServiceManagement
import Testing
@testable import ChallengeSyncKit
@testable import DailyChallengeProof

@MainActor private final class FakeLoginItem: LoginItemService {
    var status = SMAppService.Status.notRegistered
    var registeredStatus = SMAppService.Status.enabled
    var registrations = 0
    var removals = 0
    var fail = false
    func register() throws {
        registrations += 1
        if fail { throw CocoaError(.fileWriteNoPermission) }
        status = registeredStatus
    }
    func unregister() throws {
        removals += 1
        if fail { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}

@Test @MainActor func loginItemNeverRegistersOnInitializationOrRefresh() {
    let service = FakeLoginItem()
    let model = LaunchAtLoginController(service: service)
    #expect(!model.isRequested)
    for status: SMAppService.Status in [.notRegistered, .enabled, .requiresApproval, .notFound] {
        service.status = status
        model.refresh()
        #expect(model.status == status)
    }
    #expect(service.registrations == 0 && service.removals == 0)
}

@Test @MainActor func loginItemExplicitOnAndOff() {
    let service = FakeLoginItem()
    let model = LaunchAtLoginController(service: service)
    model.setRequested(true)
    #expect(model.status == .enabled && model.isRequested)
    #expect(service.registrations == 1)
    model.setRequested(false)
    #expect(model.status == .notRegistered && !model.isRequested)
    #expect(service.removals == 1 && model.errorMessage == nil)
}

@Test @MainActor func loginItemApprovalCanBeCancelledOrGrantedExternally() {
    let service = FakeLoginItem()
    service.registeredStatus = .requiresApproval
    let model = LaunchAtLoginController(service: service)
    model.setRequested(true)
    #expect(model.isRequested && model.status == .requiresApproval)
    #expect(model.statusMessage.contains("System Settings > General > Login Items"))
    model.setRequested(false)
    #expect(!model.isRequested && service.removals == 1)
    service.status = .enabled
    model.refresh()
    #expect(model.status == .enabled)
    #expect(service.registrations == 1)
}

@Test @MainActor func loginItemFailuresReflectSystemRatherThanRequestedValue() {
    let service = FakeLoginItem()
    let model = LaunchAtLoginController(service: service)
    service.fail = true
    model.setRequested(true)
    #expect(!model.isRequested && model.errorMessage != nil)
    service.status = .enabled
    model.setRequested(false)
    #expect(model.isRequested && model.errorMessage != nil)
    service.fail = false
    model.setRequested(false)
    #expect(!model.isRequested && model.errorMessage == nil)
    service.status = .notFound
    model.refresh()
    #expect(!model.isRequested && model.statusMessage.contains("not found"))
}
