import Foundation
import ServiceManagement

// MARK: - Login Item Helper
class LoginItemUtility {
    static func setLoginItemEnabled(_ enabled: Bool) {
        if enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {
                LoggingUtility.shared.log("Error enabling login item: \(error.localizedDescription)")
            }
        } else {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                LoggingUtility.shared.log("Error disabling login item: \(error.localizedDescription)")
            }
        }
    }

    static func isLoginItemEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
}