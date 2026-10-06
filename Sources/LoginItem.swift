import Foundation
import ServiceManagement

/// Wraps SMAppService so the popover can toggle "Launch at login".
@MainActor
final class LoginItem: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            apply()
        }
    }

    init() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    func refresh() {
        let enabled = SMAppService.mainApp.status == .enabled
        if enabled != isEnabled { isEnabled = enabled }
    }

    private func apply() {
        let service = SMAppService.mainApp
        do {
            if isEnabled {
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("Countdown: failed to update login item: \(error.localizedDescription)")
            isEnabled = service.status == .enabled
        }
    }
}
