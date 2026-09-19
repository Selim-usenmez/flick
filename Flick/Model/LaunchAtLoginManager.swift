import ServiceManagement
import Observation

/// Whether Flick is registered to launch automatically at login.
enum LaunchAtLoginStatus {
    case disabled
    case enabled
    /// Registered, but the user still needs to approve it in System Settings — happens
    /// right after `register()`, or if they later revoke it from there.
    case requiresApproval
}

/// Registers Flick itself (no separate helper target) to launch at login, via the modern
/// `SMAppService` API.
@Observable
final class LaunchAtLoginManager {
    private(set) var status: LaunchAtLoginStatus = LaunchAtLoginManager.currentStatus()

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Swallowed deliberately — `status` below reflects whatever actually happened
            // (e.g. a denied request) rather than the requested change.
        }
        status = LaunchAtLoginManager.currentStatus()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func currentStatus() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .disabled
        }
    }
}
