import SwiftUI

@main
struct BrewBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(appState: appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About BrewBar") {
                    BrewBarAbout.presentStandardPanel()
                }
            }
        }

        Settings {
            SettingsView()
        }
        .defaultSize(width: 680, height: 720)
    }
}

struct MenuBarContent: View {
    @Bindable var appState: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            Text(appState.statusText)

            Text(appState.lastCheckedText)

            Text(appState.nextCheckText)

            Button("View Packages...") {
                appState.showOutdatedPackagesWindow()
            }
            .disabled(!appState.isViewPackagesEnabled)

            Divider()

            Menu("Check Interval") {
                ForEach(appState.sortedIntervalOptions) { option in
                    Toggle(isOn: Binding(
                        get: { appState.getCurrentInterval() == option.value },
                        set: { _ in appState.setInterval(option.value) }
                    )) {
                        Text(option.name)
                    }
                }
            }

            Button("Update Homebrew") {
                appState.triggerUpdate()
            }
            .keyboardShortcut("u")

            Button("Upgrade All Packages") {
                appState.triggerUpgradeAll()
            }
            .keyboardShortcut("U")

            if appState.isChecking {
                Text("Operation in progress...")
            }

            Divider()

            SettingsLink {
                Text("Settings...")
            }
            .keyboardShortcut(",")

            Divider()

            Text("Version \(appState.appVersionString)")

            Button("About BrewBar") {
                BrewBarAbout.presentStandardPanel()
            }

            Button("View on GitHub") {
                if let url = URL(string: "https://github.com/joshbeard/BrewBar") {
                    openURL(url)
                }
            }

            Divider()

            Button("Quit BrewBar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .alert("Application Updated", isPresented: $appState.showRelaunchPrompt) {
            Button("Relaunch Now") {
                appState.performRelaunchFromPrompt()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text("BrewBar was updated to a new version. Relaunch now to apply the changes?")
        }
    }
}
