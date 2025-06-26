@testable import BrewBar
import Foundation
import Testing

struct BrewBarTests {
    @Test func parsePackagesWithVersions_standardFormat() {
        let manager = BrewBarManager()
        let output = "wget (1.21.3) != 1.21.4\ncurl (7.85.0) < 7.86.0"
        let packages = manager.parsePackagesWithVersions(from: output)

        #expect(packages.count == 2)
        #expect(packages[0].name == "wget")
        #expect(packages[0].currentVersion == "1.21.3")
        #expect(packages[0].availableVersion == "1.21.4")
        #expect(packages[1].name == "curl")
    }

    @Test func parsePackagesWithVersions_arrowFormat() {
        let manager = BrewBarManager()
        let output = "firefox 120.0 -> 121.0"
        let packages = manager.parsePackagesWithVersions(from: output)

        #expect(packages.count == 1)
        #expect(packages[0].name == "firefox")
        #expect(packages[0].currentVersion == "120.0")
        #expect(packages[0].availableVersion == "121.0")
    }

    @Test func parsePackagesWithVersions_emptyOutput() {
        let manager = BrewBarManager()
        let packages = manager.parsePackagesWithVersions(from: "")
        #expect(packages.isEmpty)
    }

    @Test func parsePackagesWithVersions_skipsHeaderLines() {
        let manager = BrewBarManager()
        let output = "==> Outdated\nChecking for updates\nwget (1.0) != 2.0"
        let packages = manager.parsePackagesWithVersions(from: output)
        #expect(packages.count == 1)
        #expect(packages[0].name == "wget")
    }

    @Test func intervalOptions_containsDefaults() {
        let state = AppState()
        let options = state.intervalOptions

        #expect(options["Every Hour"] == 3600)
        #expect(options["Every Day"] == 86400)
        #expect(options["Manually"] == 0)
    }

    @Test func menuBarIcon_defaultState() {
        let state = AppState()
        #expect(state.menuBarIcon == "mug")
    }

    @Test func menuBarIcon_afterCheck_noUpdates() {
        let state = AppState()
        state.lastCheckTime = Date()
        state.currentOutdatedPackages = []
        state.lastCheckError = false
        #expect(state.menuBarIcon == "checkmark.circle")
    }

    @Test func menuBarIcon_withUpdates() {
        let state = AppState()
        state.lastCheckTime = Date()
        state.currentOutdatedPackages = [
            PackageInfo(name: "test", currentVersion: "1.0", availableVersion: "2.0", source: "formula"),
        ]
        #expect(state.menuBarIcon == "mug.fill")
    }

    @Test func menuBarIcon_error() {
        let state = AppState()
        state.lastCheckError = true
        #expect(state.menuBarIcon == "xmark.circle")
    }

    @Test func statusText_upToDate() {
        let state = AppState()
        state.currentOutdatedPackages = []
        state.lastCheckError = false
        state.isChecking = false
        #expect(state.statusText == "Homebrew is up to date")
    }

    @Test func statusText_checking() {
        let state = AppState()
        state.isChecking = true
        #expect(state.statusText == "Checking for updates...")
    }
}
