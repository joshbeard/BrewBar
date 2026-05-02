import Foundation
import Observation
import SwiftUI

@Observable
class PackageViewState {
    var isCheckingForUpdates: Bool = false
    var inlineTerminalTitle: String?
    var inlineTerminalArguments: [String]?
    var inlineTerminalSessionID: UUID?
    var isTerminalProcessRunning: Bool = false

    var hasInlineTerminal: Bool {
        inlineTerminalSessionID != nil
    }
}

// MARK: - Brew info sheet target (outdated or installed row)

/// Minimal context for `brew info` / `brew info --cask`.
private struct BrewInfoSheetPackage: Identifiable, Hashable {
    var id: String {
        name
    }
    let name: String
    let source: String

    init(_ package: PackageInfo) {
        name = package.name
        source = package.source
    }

    init(_ package: InstalledPackageInfo) {
        name = package.name
        source = package.source
    }
}

private struct PendingUninstall: Identifiable {
    let id = UUID()
    let taskTitle: String
    let arguments: [String]
    let dialogTitle: String
    let message: String
}

// MARK: - SwiftUI View for Homebrew Packages

struct OutdatedPackagesView: View {
    @Bindable var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(TerminalPreferences.appearanceKey) private var terminalAppearanceRaw = TerminalAppearanceMode.matchSystem.rawValue
    @AppStorage(TerminalPreferences.presetKey) private var terminalPresetRaw = TerminalColorPreset.catppuccin.rawValue
    @State private var viewState = PackageViewState()
    @State private var selectedPackages: Set<String> = []
    @State private var selectedInstalledPackages: Set<String> = []
    @State private var selectedTab = 0
    @State private var searchText = ""
    @State private var showDismissTerminalConfirmation = false
    @State private var brewInfoSheetPackage: BrewInfoSheetPackage?
    @State private var pendingUninstall: PendingUninstall?

    private let brewExecutablePath = BrewBarUtility.shared.brewPath ?? "/opt/homebrew/bin/brew"

    private var packagesInfo: [PackageInfo] {
        appState.currentOutdatedPackages
    }
    private var installedPackages: [InstalledPackageInfo] {
        appState.currentInstalledPackages
    }
    private var errorOccurred: Bool {
        appState.lastCheckError
    }

    private var resolvedTerminalScheme: ColorScheme {
        let mode = TerminalAppearanceMode(rawValue: terminalAppearanceRaw) ?? .matchSystem
        switch mode {
            case .matchSystem: return colorScheme
            case .dark: return .dark
            case .light: return .light
        }
    }

    private var terminalColorPreset: TerminalColorPreset {
        TerminalColorPreset(rawValue: terminalPresetRaw) ?? .catppuccin
    }

    var body: some View {
        Group {
            if viewState.hasInlineTerminal,
               let title = viewState.inlineTerminalTitle,
               let args = viewState.inlineTerminalArguments,
               let sessionID = viewState.inlineTerminalSessionID
            {
                inlineTerminalPane(title: title, arguments: args, sessionID: sessionID)
            } else {
                packagesListPane
            }
        }
        .padding()
        .frame(minWidth: 700, minHeight: 520)
        .alert("Task Still Running", isPresented: $showDismissTerminalConfirmation) {
            Button("Leave Anyway", role: .destructive) {
                clearInlineTerminal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Going back will stop the current Homebrew task. Are you sure?")
        }
        .alert("Task Still Running", isPresented: $appState.showClosePackagesWhileBrewRunningAlert) {
            Button("Close Anyway", role: .destructive) {
                appState.confirmPackagesWindowCloseWhileTaskRunning()
            }
            Button("Cancel", role: .cancel) {
                appState.cancelPackagesWindowCloseConfirmation()
            }
        } message: {
            Text("Closing this window will stop the current Homebrew task. Are you sure you want to close it?")
        }
        .onChange(of: appState.pendingSheetAction) { _, action in
            if let action {
                switch action {
                    case .check: handlePendingCheckAction()
                    case .update: handlePendingUpdateAction()
                    case .upgradeAll: handlePendingUpgradeAllAction()
                }
                appState.pendingSheetAction = nil
            }
        }
        .sheet(item: $brewInfoSheetPackage) { package in
            BrewPackageInfoSheet(package: package)
        }
        .alert(
            pendingUninstall?.dialogTitle ?? "Uninstall",
            isPresented: Binding(
                get: { pendingUninstall != nil },
                set: { if !$0 { pendingUninstall = nil } }
            ),
            presenting: pendingUninstall,
            actions: { prompt in
                Button("Uninstall", role: .destructive) {
                    startInlineBrewTask(title: prompt.taskTitle, arguments: prompt.arguments)
                    pendingUninstall = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingUninstall = nil
                }
            },
            message: { prompt in
                Text(prompt.message)
            }
        )
    }

    private var packagesListPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            if errorOccurred {
                Text("Error Checking for Updates")
                    .font(.headline)
                    .foregroundColor(.red)
                    .padding(.bottom, 5)

                Text("There was an error checking for outdated packages. This could be due to network issues or Homebrew configuration.")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 10)

                Button("Check Again") {
                    viewState.isCheckingForUpdates = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewState.isCheckingForUpdates)
            } else {
                TabView(selection: $selectedTab) {
                    VStack {
                        OutdatedPackagesTabView()
                    }
                    .tabItem {
                        Label("Outdated", systemImage: "arrow.up.circle")
                    }
                    .tag(0)
                    .onChange(of: selectedTab) { _, newValue in
                        if newValue != 0 { searchText = "" }
                    }

                    VStack {
                        InstalledPackagesTabView()
                    }
                    .tabItem {
                        Label("Installed", systemImage: "list.bullet")
                    }
                    .tag(1)
                    .onChange(of: selectedTab) { _, newValue in
                        if newValue != 1 { searchText = "" }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if viewState.isCheckingForUpdates {
                        ZStack {
                            Color(.windowBackgroundColor).opacity(0.8)
                                .edgesIgnoringSafeArea(.all)

                            VStack(spacing: 20) {
                                ProgressView()
                                    .scaleEffect(2.0)
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.bottom, 10)

                                Text("Checking for updates...")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.controlBackgroundColor))
                                    .shadow(radius: 10)
                            )
                            .accessibility(label: Text("Checking for updates"))
                        }
                        .transition(.opacity)
                        .animation(.easeInOut, value: viewState.isCheckingForUpdates)
                    }
                }
            }
        }
    }

    /// Fixed header band + terminal height = remaining space. Without this, a flexible
    /// `VStack` lets the terminal claim space first when the window shrinks, clipping the
    /// back button and title (especially after a tall resize).
    private func inlineTerminalPane(title: String, arguments: [String], sessionID: UUID) -> some View {
        let headerSpacing: CGFloat = 8
        let headerSlotHeight: CGFloat = 76

        return GeometryReader { geo in
            let terminalH = max(100, geo.size.height - headerSlotHeight - headerSpacing)
            VStack(alignment: .leading, spacing: headerSpacing) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button("Back to Packages") {
                            if viewState.isTerminalProcessRunning {
                                showDismissTerminalConfirmation = true
                            } else {
                                clearInlineTerminal()
                            }
                        }
                        Spacer()
                    }

                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: geo.size.width, height: headerSlotHeight, alignment: .topLeading)

                SwiftTermView(
                    executablePath: brewExecutablePath,
                    arguments: arguments,
                    resolvedTerminalScheme: resolvedTerminalScheme,
                    colorPreset: terminalColorPreset,
                    onProcessEnd: { commandArgs, exitCode in
                        appState.handleTaskCompletion(commandArgs: commandArgs, exitCode: exitCode)
                        viewState.isTerminalProcessRunning = false
                        appState.isPackagesWindowBrewTaskRunning = false
                        if let code = exitCode, code == 0,
                           commandArgs == BrewBarManager.shared.updateCommand
                        {
                            clearInlineTerminal()
                        }
                    }
                )
                .id(sessionID)
                .frame(width: geo.size.width, height: terminalH)
                .clipped()
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startInlineBrewTask(title: String, arguments: [String]) {
        viewState.inlineTerminalTitle = title
        viewState.inlineTerminalArguments = arguments
        viewState.inlineTerminalSessionID = UUID()
        viewState.isTerminalProcessRunning = true
        appState.isPackagesWindowBrewTaskRunning = true
    }

    private func clearInlineTerminal() {
        viewState.inlineTerminalTitle = nil
        viewState.inlineTerminalArguments = nil
        viewState.inlineTerminalSessionID = nil
        viewState.isTerminalProcessRunning = false
        appState.isPackagesWindowBrewTaskRunning = false
    }

    private func queueUninstallConfirmation(taskTitle: String, arguments: [String]) {
        let names = BrewBarUtility.packageNames(fromUninstallArguments: arguments)
        let dialogTitle: String
        let message: String
        if names.isEmpty {
            dialogTitle = "Uninstall packages?"
            message = "Homebrew will run uninstall with the chosen options. This cannot be undone from BrewBar."
        } else if names.count == 1, let only = names.first {
            dialogTitle = "Uninstall “\(only)”?"
            message = "Homebrew will remove this package from your system. This cannot be undone from BrewBar."
        } else {
            dialogTitle = "Uninstall \(names.count) packages?"
            message = "Homebrew will remove: \(names.joined(separator: ", "))\n\nThis cannot be undone from BrewBar."
        }
        pendingUninstall = PendingUninstall(
            taskTitle: taskTitle,
            arguments: arguments,
            dialogTitle: dialogTitle,
            message: message
        )
    }

    private func runInstalledBrewTask(title: String, arguments: [String]) {
        if arguments.first == "uninstall" {
            queueUninstallConfirmation(taskTitle: title, arguments: arguments)
        } else {
            startInlineBrewTask(title: title, arguments: arguments)
        }
    }

    private func handlePendingCheckAction() {
        LoggingUtility.shared.log("Running outdated check from menu (inline terminal).")
        startInlineBrewTask(title: "Checking for Outdated Packages...", arguments: ["outdated", "--verbose"])
    }

    private func handlePendingUpdateAction() {
        LoggingUtility.shared.log("Running brew update from menu (inline terminal).")
        startInlineBrewTask(title: "Updating Homebrew...", arguments: BrewBarManager.shared.updateCommand)
    }

    private func handlePendingUpgradeAllAction() {
        LoggingUtility.shared.log("Running upgrade --all from menu (inline terminal).")
        startInlineBrewTask(title: "Upgrading All Packages...", arguments: BrewBarManager.shared.upgradeCommand)
    }

    func OutdatedPackagesTabView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if packagesInfo.isEmpty {
                outdatedTabAllUpToDateContent
            } else {
                Text("Outdated Homebrew Packages (\(filteredOutdatedPackages.count))")
                    .font(.headline)
                    .padding(.bottom, 5)

                SearchField(searchText: $searchText)

                if filteredOutdatedPackages.isEmpty && !searchText.isEmpty {
                    Text("No matching packages found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if !filteredOutdatedPackages.isEmpty {
                    outdatedTabToolbar
                        .padding(.horizontal)
                    outdatedTabScrollList
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var outdatedTabAllUpToDateContent: some View {
        VStack(spacing: 15) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)
                .foregroundColor(.green)

            Text("All packages are up to date!")
                .font(.title2)
                .foregroundColor(.secondary)

            Button("Check for Updates") {
                startInlineBrewTask(title: "Updating Homebrew Database...", arguments: BrewBarManager.shared.updateCommand)
            }
            .padding(.top, 10)
            .disabled(viewState.isCheckingForUpdates)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var outdatedTabToolbar: some View {
        HStack {
            Button("Select All") {
                selectedPackages = Set(filteredOutdatedPackages.map { $0.name })
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .disabled(viewState.isCheckingForUpdates)

            Button("Deselect All") {
                selectedPackages.removeAll()
            }
            .buttonStyle(.borderless)
            .font(.footnote)
            .disabled(viewState.isCheckingForUpdates)

            Spacer()

            Button("Check for Updates") {
                startInlineBrewTask(title: "Updating Homebrew Database...", arguments: BrewBarManager.shared.updateCommand)
            }
            .disabled(viewState.isCheckingForUpdates)

            Button("Upgrade Selected") {
                let packageNames = Array(selectedPackages)
                if !packageNames.isEmpty {
                    startInlineBrewTask(title: "Upgrading Selected...", arguments: ["upgrade"] + packageNames)
                }
            }
            .disabled(selectedPackages.isEmpty || viewState.isCheckingForUpdates)

            Button("Upgrade All") {
                startInlineBrewTask(title: "Upgrading All Packages...", arguments: BrewBarManager.shared.upgradeCommand)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewState.isCheckingForUpdates)
        }
    }

    private var outdatedTabScrollList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text("Select").fontWeight(.bold).frame(width: 60, alignment: .leading)
                    Text("Package").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Current").fontWeight(.bold).frame(width: 80, alignment: .leading)
                    Text("Available").fontWeight(.bold).frame(width: 80, alignment: .leading)
                    Text("Source").fontWeight(.bold).frame(width: 120, alignment: .leading)
                    Text("Actions").fontWeight(.bold).frame(width: 130, alignment: .center)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))

                ForEach(Array(filteredOutdatedPackages.enumerated()), id: \.element.id) { index, package in
                    outdatedPackageRow(index: index, package: package)
                }
            }
        }
    }

    private func outdatedPackageRow(index: Int, package: PackageInfo) -> some View {
        HStack {
            Checkbox(isChecked: Binding(
                get: { selectedPackages.contains(package.name) },
                set: { isSelected in
                    if isSelected { selectedPackages.insert(package.name) }
                    else { selectedPackages.remove(package.name) }
                }
            ))
            .frame(width: 60, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    brewInfoSheetPackage = BrewInfoSheetPackage(package)
                } label: {
                    Text(package.name)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    brewInfoSheetPackage = BrewInfoSheetPackage(package)
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Show brew info for \(package.name)")
            }

            Text(package.currentVersion).foregroundColor(.secondary).frame(width: 80, alignment: .leading)
            Text(package.availableVersion).foregroundColor(.blue).frame(width: 80, alignment: .leading)
            Text(package.source).foregroundColor(.secondary).frame(width: 120, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    startInlineBrewTask(title: "Upgrading \(package.name)...", arguments: ["upgrade", package.name])
                } label: {
                    Image(systemName: "arrow.up.circle").foregroundColor(.blue)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Upgrade \(package.name)")

                Button {
                    let isCask = package.source == "cask"
                    var args = ["uninstall"]
                    if isCask { args.append("--cask") }
                    args.append(package.name)
                    queueUninstallConfirmation(
                        taskTitle: "Uninstalling \(package.name)...",
                        arguments: args
                    )
                } label: {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Uninstall \(package.name)")
            }
            .frame(width: 130, alignment: .center)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(selectedPackages.contains(package.name) ? Color.blue.opacity(0.1) : (index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05)))
    }

    func InstalledPackagesTabView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if installedPackages.isEmpty {
                VStack(spacing: 15) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.5)
                        .padding(.bottom, 10)

                    Text("Loading installed packages...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Installed Homebrew Packages (\(filteredInstalledPackages.count))")
                    .font(.headline)
                    .padding(.bottom, 5)

                SearchField(searchText: $searchText)

                if filteredInstalledPackages.isEmpty && !searchText.isEmpty {
                    Text("No matching packages found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else {
                    HStack {
                        Button("Deselect All") {
                            selectedInstalledPackages.removeAll()
                        }
                        .buttonStyle(.borderless)
                        .font(.footnote)

                        Spacer()

                        Button("Uninstall Selected") {
                            let names = selectedInstalledPackages.sorted()
                            guard !names.isEmpty else { return }
                            var args = ["uninstall"]
                            for name in names {
                                let isCask = installedPackages.first { $0.name == name }?.source == "cask"
                                if isCask == true { args.append("--cask") }
                                args.append(name)
                            }
                            let title: String
                            if names.count == 1 {
                                title = "Uninstalling \(names[0])..."
                            } else {
                                title = "Uninstalling \(names.count) packages..."
                            }
                            queueUninstallConfirmation(taskTitle: title, arguments: args)
                        }
                        .disabled(selectedInstalledPackages.isEmpty)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)

                    InstalledPackagesTable(
                        packages: filteredInstalledPackages,
                        selectedPackages: $selectedInstalledPackages,
                        onRunBrewTask: { title, args in
                            runInstalledBrewTask(title: title, arguments: args)
                        },
                        onShowPackageInfo: { brewInfoSheetPackage = BrewInfoSheetPackage($0) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var filteredOutdatedPackages: [PackageInfo] {
        if searchText.isEmpty { return packagesInfo }
        return packagesInfo.filter { package in
            package.name.localizedCaseInsensitiveContains(searchText) ||
                package.source.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredInstalledPackages: [InstalledPackageInfo] {
        if searchText.isEmpty { return installedPackages }
        return installedPackages.filter { package in
            package.name.localizedCaseInsensitiveContains(searchText) ||
                package.source.localizedCaseInsensitiveContains(searchText) ||
                package.version.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Subviews

    private struct InstalledPackagesTable: View {
        let packages: [InstalledPackageInfo]
        @Binding var selectedPackages: Set<String>
        var onRunBrewTask: (String, [String]) -> Void
        var onShowPackageInfo: (InstalledPackageInfo) -> Void

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("Select").fontWeight(.bold).frame(width: 60, alignment: .leading)
                        Text("Package").fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Version").fontWeight(.bold).frame(width: 100, alignment: .leading)
                        Text("Source").fontWeight(.bold).frame(width: 120, alignment: .leading)
                        Text("Actions").fontWeight(.bold).frame(width: 60, alignment: .center)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))

                    ForEach(Array(packages.enumerated()), id: \.element.id) { index, package in
                        HStack {
                            Checkbox(isChecked: Binding(
                                get: { selectedPackages.contains(package.name) },
                                set: { isSelected in
                                    if isSelected { selectedPackages.insert(package.name) }
                                    else { selectedPackages.remove(package.name) }
                                }
                            ))
                            .frame(width: 60, alignment: .leading)

                            HStack(spacing: 6) {
                                Button {
                                    onShowPackageInfo(package)
                                } label: {
                                    Text(package.name)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    onShowPackageInfo(package)
                                } label: {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.borderless)
                                .help("Show brew info for \(package.name)")
                            }

                            Text(package.version).foregroundColor(.secondary).frame(width: 100, alignment: .leading)
                            Text(package.source).foregroundColor(.secondary).frame(width: 120, alignment: .leading)

                            Button {
                                let isCask = package.source == "cask"
                                var args = ["uninstall"]
                                if isCask { args.append("--cask") }
                                args.append(package.name)
                                onRunBrewTask("Uninstalling \(package.name)...", args)
                            } label: {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Uninstall \(package.name)")
                            .frame(width: 60, alignment: .center)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(selectedPackages.contains(package.name) ? Color.blue.opacity(0.1) : (index % 2 == 0 ? Color.clear : Color.gray.opacity(0.05)))
                    }
                }
            }
        }
    }

    /// Sheet that runs `brew info` / `brew info --cask` and shows plain-text output (URLs, description, deps, etc.).
    private struct BrewPackageInfoSheet: View {
        let package: BrewInfoSheetPackage
        @Environment(\.dismiss) private var dismiss
        @State private var output = ""
        @State private var isLoading = true
        @State private var errorMessage: String?

        var body: some View {
            NavigationStack {
                Group {
                    if isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding()
                    } else {
                        ScrollView {
                            Group {
                                if output.isEmpty {
                                    Text("(No output from brew info.)")
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(BrewInfoFormatting.attributedString(from: output))
                                        .textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                    }
                }
                .navigationTitle(package.name)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .frame(minWidth: 520, minHeight: 440)
            .task(id: package.id) {
                await loadInfo()
            }
        }

        private func brewInfoArguments() -> [String] {
            if package.source == "cask" {
                return ["info", "--cask", package.name]
            }
            return ["info", package.name]
        }

        private func loadInfo() async {
            await MainActor.run {
                isLoading = true
                errorMessage = nil
                output = ""
            }
            do {
                let (text, code) = try await BrewBarUtility.shared.runBrewCommand(brewInfoArguments())
                await MainActor.run {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    isLoading = false
                    if code != 0, trimmed.isEmpty {
                        errorMessage = "brew info exited with status \(code) and produced no output."
                        output = ""
                    } else {
                        errorMessage = nil
                        output =
                            code != 0
                                ? "Exit status \(code) (output may still be useful):\n\n\(trimmed)"
                                : trimmed
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Reusable Components

private struct SearchField: View {
    @Binding var searchText: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search packages", text: $searchText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.bottom, 10)
    }
}

struct Checkbox: View {
    @Binding var isChecked: Bool

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundColor(isChecked ? .blue : .gray)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}
