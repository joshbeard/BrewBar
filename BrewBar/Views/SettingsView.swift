import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            CommandsSettingsView()
                .tabItem { Label("Commands", systemImage: "terminal") }
            TerminalSettingsView()
                .tabItem { Label("Terminal", systemImage: "rectangle.inset.filled.and.person.filled") }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 620)
        .background(ActivateSettingsHostWindow())
        .onAppear {
            DockVisibility.promoteToRegularApp()
        }
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    private let appState = AppState.shared

    @State private var customIntervalName = ""
    @State private var customIntervalSeconds = ""
    @State private var customIntervalsList: [IntervalOption] = []
    @State private var showInvalidIntervalAlert = false
    @State private var loginItemEnabled: Bool
    @State private var notificationsEnabled: Bool

    init() {
        _loginItemEnabled = State(initialValue: LoginItemUtility.isLoginItemEnabled())
        let notifEnabled = UserDefaults.standard.object(forKey: BrewBarNotificationPreferences.userToggleKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: BrewBarNotificationPreferences.userToggleKey)
        _notificationsEnabled = State(initialValue: notifEnabled)
    }

    var body: some View {
        Form {
            Section("Update Check Interval") {
                Picker("Interval", selection: Binding(
                    get: { appState.getCurrentInterval() },
                    set: { appState.setInterval($0) }
                )) {
                    ForEach(appState.sortedIntervalOptions) { option in
                        Text(option.name).tag(option.value)
                    }
                }
            }

            Section("Custom Intervals") {
                LabeledContent {
                    HStack(spacing: 8) {
                        TextField("", text: $customIntervalName, prompt: Text("Name"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                        TextField("", text: $customIntervalSeconds, prompt: Text("Seconds"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Button("Add") { addCustomInterval() }
                    }
                } label: {
                    EmptyView()
                }

                ForEach(customIntervalsList, id: \.name) { interval in
                    HStack {
                        Text(interval.name)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(intervalSecondsLabel(for: interval.value))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button {
                            removeCustomInterval(named: interval.name)
                        } label: {
                            Text("Remove")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if customIntervalsList.isEmpty {
                    Text("No custom intervals added.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }

            Section("Startup & Notifications") {
                Toggle("Start BrewBar when you log in", isOn: $loginItemEnabled)
                    .onChange(of: loginItemEnabled) { _, newValue in
                        appState.setLoginItemEnabled(newValue)
                    }

                Toggle("Show notifications when updates are available", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: BrewBarNotificationPreferences.userToggleKey)
                        LoggingUtility.shared.log("Notifications \(newValue ? "enabled" : "disabled")")
                    }
            }

            Section("Debug & Diagnostics") {
                Button("Send Test Notification") {
                    Task { @MainActor in
                        await NotificationManager.shared.sendTestNotification()
                    }
                }
                Button("Open Logs Folder") {
                    NSWorkspace.shared.open(LoggingUtility.logDirectoryURL)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reloadCustomIntervals() }
        .alert("Invalid Input", isPresented: $showInvalidIntervalAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid name and a positive number of seconds.")
        }
    }

    // MARK: - Custom Intervals

    private func reloadCustomIntervals() {
        guard let dict = UserDefaults.standard.dictionary(forKey: appState.customIntervalsKey) as? [String: TimeInterval] else {
            customIntervalsList = []
            return
        }
        customIntervalsList = dict.map { IntervalOption(name: $0.key, value: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func intervalSecondsLabel(for value: TimeInterval) -> String {
        let n = Int(value)
        if n == 1 { return "1 second" }
        return "\(n) seconds"
    }

    private func addCustomInterval() {
        let name = customIntervalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let secondsString = customIntervalSeconds.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, let seconds = TimeInterval(secondsString), seconds > 0 else {
            showInvalidIntervalAlert = true
            return
        }

        var dict = UserDefaults.standard.dictionary(forKey: appState.customIntervalsKey) as? [String: TimeInterval] ?? [:]
        dict[name] = seconds
        UserDefaults.standard.set(dict, forKey: appState.customIntervalsKey)

        customIntervalName = ""
        customIntervalSeconds = ""
        reloadCustomIntervals()
        appState.scheduleUpdateTimer()
    }

    private func removeCustomInterval(named name: String) {
        var dict = UserDefaults.standard.dictionary(forKey: appState.customIntervalsKey) as? [String: TimeInterval] ?? [:]
        dict.removeValue(forKey: name)
        UserDefaults.standard.set(dict, forKey: appState.customIntervalsKey)
        reloadCustomIntervals()
        appState.scheduleUpdateTimer()
    }
}

// MARK: - Terminal (embedded SwiftTerm)

struct TerminalSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TerminalPreferences.appearanceKey) private var appearanceRaw: String = TerminalAppearanceMode.matchSystem.rawValue
    @AppStorage(TerminalPreferences.presetKey) private var presetRaw: String = TerminalColorPreset.catppuccin.rawValue

    private var previewScheme: ColorScheme {
        let mode = TerminalAppearanceMode(rawValue: appearanceRaw) ?? .matchSystem
        switch mode {
        case .matchSystem: return colorScheme
        case .dark: return .dark
        case .light: return .light
        }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Light / dark", selection: $appearanceRaw) {
                    ForEach(TerminalAppearanceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Text("“Match system” follows macOS light or dark mode for the embedded terminal only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Color preset") {
                Picker("Preset", selection: $presetRaw) {
                    ForEach(TerminalColorPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset.rawValue)
                    }
                }
                Text("Catppuccin uses fixed Mocha (dark) and Latte (light) colors. System uses neutral light or dark gray chrome that follows the mode chosen above, independent of the rest of the app window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                terminalPreviewContent
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            } header: {
                Text("Preview")
            } footer: {
                Text("Sample text uses the same background, foreground, and completion colors as the embedded terminal in the packages window.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var terminalPreviewContent: some View {
        let preset = TerminalColorPreset(rawValue: presetRaw) ?? .catppuccin
        let nsColors = preset.colors(for: previewScheme)
        let completion = preset.previewCompletionColors(for: previewScheme)

        VStack(alignment: .leading, spacing: 8) {
            Text("$ brew update")
            Text("==> Updating Homebrew …")
            Text("[Process completed successfully]")
                .foregroundStyle(completion.success)
            Text("[Process completed with error code 1]")
                .foregroundStyle(completion.failure)
        }
        .font(.system(.callout, design: .monospaced))
        .foregroundStyle(Color(nsColor: nsColors.foreground))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: nsColors.background))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Commands Settings

struct CommandsSettingsView: View {
    @State private var updateCommandString: String
    @State private var upgradeCommandString: String
    @State private var showSavedAlert = false
    @State private var showResetAlert = false

    init() {
        _updateCommandString = State(initialValue: BrewBarManager.shared.updateCommand.joined(separator: " "))
        _upgradeCommandString = State(initialValue: BrewBarManager.shared.upgradeCommand.joined(separator: " "))
    }

    var body: some View {
        Form {
            Section("Homebrew Commands") {
                LabeledContent("Update Command") {
                    TextField("", text: $updateCommandString, prompt: Text("e.g. update"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                LabeledContent("Upgrade Command") {
                    TextField("", text: $upgradeCommandString, prompt: Text("e.g. upgrade"))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                }

                Text("Enter commands without the brew prefix. Use spaces between arguments (for example upgrade --greedy).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Reset to Defaults") { resetCommands() }
                Spacer()
                Button("Save Commands") { saveCommands() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .alert("Commands Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your custom Homebrew commands have been saved.")
        }
        .alert("Commands Reset", isPresented: $showResetAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Homebrew commands have been reset to their default values.")
        }
    }

    private func saveCommands() {
        let updateArray = updateCommandString.components(separatedBy: " ").filter { !$0.isEmpty }
        let upgradeArray = upgradeCommandString.components(separatedBy: " ").filter { !$0.isEmpty }

        if !updateArray.isEmpty {
            BrewBarManager.shared.updateCommand = updateArray
        }
        if !upgradeArray.isEmpty {
            BrewBarManager.shared.upgradeCommand = upgradeArray
        }
        showSavedAlert = true
    }

    private func resetCommands() {
        BrewBarManager.shared.updateCommand = BrewBarManager.shared.defaultUpdateCommand
        BrewBarManager.shared.upgradeCommand = BrewBarManager.shared.defaultUpgradeCommand
        updateCommandString = BrewBarManager.shared.defaultUpdateCommand.joined(separator: " ")
        upgradeCommandString = BrewBarManager.shared.defaultUpgradeCommand.joined(separator: " ")
        showResetAlert = true
    }
}

// MARK: - Settings window (accessory app)

/// When the Settings host window attaches, promote to a regular Dock app and key this window.
private struct ActivateSettingsHostWindow: NSViewRepresentable {
    final class AnchorView: NSView {
        private var activatedForWindow: ObjectIdentifier?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            let id = ObjectIdentifier(window)
            guard activatedForWindow != id else { return }
            activatedForWindow = id
            DockVisibility.promoteToRegularApp(keyWindow: window)
        }
    }

    func makeNSView(context: Context) -> NSView {
        AnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
