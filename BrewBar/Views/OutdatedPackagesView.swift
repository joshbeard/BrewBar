import Combine
import Foundation
import SwiftUI

// Notification Name for triggering check from menu
extension Notification.Name {
    static let BrewBarShouldRunCheckInSheet = Notification.Name("me.joshbeard.brewbar.runCheckInSheet")
    static let BrewBarShouldRunUpdateInSheet = Notification.Name("me.joshbeard.brewbar.runUpdateInSheet")
    static let BrewBarShouldRunUpgradeAllInSheet = Notification.Name("me.joshbeard.brewbar.runUpgradeAllInSheet")
}

// State container for the view
class PackageViewState: ObservableObject {
    @Published var isCheckingForUpdates: Bool = false
    // Add state for the embedded terminal
    @Published var showTerminalSheet: Bool = false
    @Published var terminalArgs: [String]?
    @Published var terminalTitle: String = "Terminal"
    @Published var terminalKey: UUID = UUID()
    @Published var isTerminalProcessRunning: Bool = false
}

// MARK: - SwiftUI View for Homebrew Packages

struct OutdatedPackagesView: View {
    let packagesInfo: [PackageInfo]
    let installedPackages: [InstalledPackageInfo]
    @State private var selectedPackages: Set<String> = []
    @State private var selectedInstalledPackages: Set<String> = []
    @State private var selectedTab = 0
    @State private var searchText = ""
    let errorOccurred: Bool
    @StateObject var viewState: PackageViewState

    // Callbacks to trigger external actions
    let refreshDataAfterTask: (_ commandArgs: [String], _ exitCode: Int32?) -> Void

    // Get brew path (ideally passed in or from a shared utility)
    private let brewExecutablePath = BrewBarUtility.shared.brewPath ?? "/opt/homebrew/bin/brew"

    init(packages: [PackageInfo],
         installed: [InstalledPackageInfo],
         errorOccurred: Bool = false,
         viewState: PackageViewState, // Pass the initial state
         refreshDataAfterTask: @escaping (_ commandArgs: [String], _ exitCode: Int32?) -> Void)
    {
        self.packagesInfo = packages
        self.installedPackages = installed
        self.errorOccurred = errorOccurred
        _viewState = StateObject(wrappedValue: viewState)
        self.refreshDataAfterTask = refreshDataAfterTask
    }

    var body: some View {
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
                    // Outdated Packages Tab
                    VStack {
                        OutdatedPackagesTabView()
                    }
                    .tabItem {
                        Label("Outdated", systemImage: "arrow.up.circle")
                    }
                    .tag(0)
                    .onChange(of: selectedTab) { _, newValue in
                        if newValue != 0 {
                            searchText = "" // Clear search when navigating away
                        }
                    }

                    // Installed Packages Tab
                    VStack {
                        InstalledPackagesTabView()
                    }
                    .tabItem {
                        Label("Installed", systemImage: "list.bullet")
                    }
                    .tag(1)
                    .onChange(of: selectedTab) { _, newValue in
                        if newValue != 1 {
                            searchText = "" // Clear search when navigating away
                        }
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
        .padding()
        .frame(minWidth: 700, minHeight: 350) // Increased minWidth
        .sheet(isPresented: $viewState.showTerminalSheet) {
            // Sheet content: The Terminal View
            if let args = viewState.terminalArgs {
                VStack {
                    Text(viewState.terminalTitle)
                        .font(.headline)
                        .padding(.top)

                    SwiftTermView(executablePath: brewExecutablePath,
                                  arguments: args,
                                  onProcessEnd: { commandArgs, exitCode in
                                      self.refreshDataAfterTask(commandArgs, exitCode)
                                      viewState.isTerminalProcessRunning = false
                                  })
                                  .id(viewState.terminalKey) // Force recreation when key changes
                                  .frame(minWidth: 600, minHeight: 400) // Size for the sheet

                    Button("Close") {
                        if viewState.isTerminalProcessRunning {
                            showCloseConfirmationAlert()
                        } else {
                            viewState.showTerminalSheet = false
                        }
                    }
                    .padding()
                }
            } else {
                // Fallback content if args aren't set (shouldn't happen with current logic)
                Text("Error: No command specified for terminal.")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .BrewBarShouldRunCheckInSheet)) { _ in
            handleRunCheckInSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .BrewBarShouldRunUpdateInSheet)) { _ in
            handleRunUpdateInSheet()
        }
        .onReceive(NotificationCenter.default.publisher(for: .BrewBarShouldRunUpgradeAllInSheet)) { _ in
            handleRunUpgradeAllInSheet()
        }
    }

    private func handleRunCheckInSheet() {
        LoggingUtility.shared.log("Received notification to run check in sheet.")
        viewState.terminalArgs = ["outdated", "--verbose"]
        viewState.terminalTitle = "Checking for Outdated Packages..."
        viewState.terminalKey = UUID()
        viewState.isTerminalProcessRunning = true
        viewState.showTerminalSheet = true
    }

    private func handleRunUpdateInSheet() {
        LoggingUtility.shared.log("Received notification to run update in sheet.")
        let command = BrewBarManager.shared.updateCommand // Use configured command
        viewState.terminalArgs = command
        viewState.terminalTitle = "Updating Homebrew..."
        viewState.terminalKey = UUID()
        viewState.isTerminalProcessRunning = true
        viewState.showTerminalSheet = true
    }

    private func handleRunUpgradeAllInSheet() {
        LoggingUtility.shared.log("Received notification to run upgrade all in sheet.")
        let command = BrewBarManager.shared.upgradeCommand // Use configured command
        viewState.terminalArgs = command
        viewState.terminalTitle = "Upgrading All Packages..."
        viewState.terminalKey = UUID()
        viewState.isTerminalProcessRunning = true
        viewState.showTerminalSheet = true
    }

    @ViewBuilder
    func OutdatedPackagesTabView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if packagesInfo.isEmpty {
                // Show a centered checkmark and message when no outdated packages
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
                        // Run update first to ensure the Homebrew database is refreshed
                        viewState.terminalArgs = BrewBarManager.shared.updateCommand
                        viewState.terminalTitle = "Updating Homebrew Database..."
                        viewState.terminalKey = UUID()
                        viewState.isTerminalProcessRunning = true
                        viewState.showTerminalSheet = true
                    }
                    .padding(.top, 10)
                    .disabled(viewState.isCheckingForUpdates)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Outdated Homebrew Packages (\(filteredOutdatedPackages.count))")
                    .font(.headline)
                    .padding(.bottom, 5)

                // Only show search when there are packages to display
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search packages", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.bottom, 10)

                if filteredOutdatedPackages.isEmpty && !searchText.isEmpty {
                    Text("No matching packages found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 20)
                } else if !filteredOutdatedPackages.isEmpty {
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
                            // Run update first to ensure the Homebrew database is refreshed
                            viewState.terminalArgs = BrewBarManager.shared.updateCommand
                            viewState.terminalTitle = "Updating Homebrew Database..."
                            viewState.terminalKey = UUID()
                            viewState.isTerminalProcessRunning = true
                            viewState.showTerminalSheet = true
                        }
                        .disabled(viewState.isCheckingForUpdates)

                        Button("Upgrade Selected") {
                            let packageNames = Array(selectedPackages)
                            if !packageNames.isEmpty {
                                viewState.terminalArgs = ["upgrade"] + packageNames
                                viewState.terminalTitle = "Upgrading Selected..."
                                viewState.terminalKey = UUID()
                                viewState.isTerminalProcessRunning = true
                                viewState.showTerminalSheet = true
                            }
                        }
                        .disabled(selectedPackages.isEmpty || viewState.isCheckingForUpdates)

                        Button("Upgrade All") {
                            let command = BrewBarManager.shared.upgradeCommand
                            viewState.terminalArgs = command
                            viewState.terminalTitle = "Upgrading All Packages..."
                            viewState.terminalKey = UUID()
                            viewState.isTerminalProcessRunning = true
                            viewState.showTerminalSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewState.isCheckingForUpdates)
                    }
                    .padding(.horizontal)

                    // Table of outdated packages
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            // Outdated Packages Table Header Row
                            HStack {
                                Text("Select")
                                    .fontWeight(.bold)
                                    .frame(width: 60, alignment: .leading)
                                Text("Package")
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Current")
                                    .fontWeight(.bold)
                                    .frame(width: 80, alignment: .leading)
                                Text("Available")
                                    .fontWeight(.bold)
                                    .frame(width: 80, alignment: .leading)
                                Text("Source")
                                    .fontWeight(.bold)
                                    .frame(width: 120, alignment: .leading)
                                Text("Actions")
                                    .fontWeight(.bold)
                                    .frame(width: 100, alignment: .center)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))

                            ForEach(filteredOutdatedPackages) { package in
                                HStack {
                                    Checkbox(isChecked: Binding(
                                        get: { selectedPackages.contains(package.name) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedPackages.insert(package.name)
                                            } else {
                                                selectedPackages.remove(package.name)
                                            }
                                        }
                                    ))
                                    .frame(width: 60, alignment: .leading)
                                    Text(package.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(package.currentVersion)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    Text(package.availableVersion)
                                        .foregroundColor(.blue)
                                        .frame(width: 80, alignment: .leading)
                                    // Source column with a consistent display
                                    Text(package.source)
                                        .foregroundColor(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    HStack(spacing: 10) {
                                        Button(action: {
                                            viewState.terminalArgs = ["upgrade", package.name]
                                            viewState.terminalTitle = "Upgrading \(package.name)..."
                                            viewState.terminalKey = UUID()
                                            viewState.isTerminalProcessRunning = true
                                            viewState.showTerminalSheet = true
                                        }) {
                                            Image(systemName: "arrow.up.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .help("Upgrade \(package.name)")

                                        Button(action: {
                                            let isCask = package.source == "cask"
                                            var args = ["uninstall"]
                                            if isCask { args.append("--cask") }
                                            args.append(package.name)
                                            viewState.terminalArgs = args
                                            viewState.terminalTitle = "Uninstalling \(package.name)..."
                                            viewState.terminalKey = UUID()
                                            viewState.isTerminalProcessRunning = true
                                            viewState.showTerminalSheet = true
                                        }) {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .help("Uninstall \(package.name)")
                                    }
                                    .frame(width: 100, alignment: .center)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(selectedPackages.contains(package.name) ? Color.blue.opacity(0.1) : (filteredOutdatedPackages.firstIndex(of: package)! % 2 == 0 ? Color.clear : Color.gray.opacity(0.05)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    func InstalledPackagesTabView() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if installedPackages.isEmpty {
                // Show centered message when no installed packages
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

                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search packages", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                }
                .padding(.bottom, 10)

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
                            if !selectedInstalledPackages.isEmpty {
                                if let firstPackageName = selectedInstalledPackages.first {
                                    let isCask = installedPackages.first { $0.name == firstPackageName }?.source == "cask"
                                    var args = ["uninstall"]
                                    if isCask { args.append("--cask") }
                                    args.append(firstPackageName)
                                    viewState.terminalArgs = args
                                    viewState.terminalTitle = "Uninstalling \(firstPackageName)..."
                                    viewState.terminalKey = UUID()
                                    viewState.isTerminalProcessRunning = true
                                    viewState.showTerminalSheet = true
                                }
                            }
                        }
                        .disabled(selectedInstalledPackages.isEmpty)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)

                    // Replace ScrollView with the new struct
                    InstalledPackagesTable(
                        packages: filteredInstalledPackages,
                        selectedPackages: $selectedInstalledPackages,
                        viewState: viewState // Pass the viewState
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // Computed properties for filtered package lists
    private var filteredOutdatedPackages: [PackageInfo] {
        if searchText.isEmpty {
            return packagesInfo
        } else {
            return packagesInfo.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.source.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private var filteredInstalledPackages: [InstalledPackageInfo] {
        if searchText.isEmpty {
            return installedPackages
        } else {
            return installedPackages.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.source.localizedCaseInsensitiveContains(searchText) ||
                    $0.version.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    // MARK: - Private Subviews

    // New private struct for the installed packages table
    private struct InstalledPackagesTable: View {
        let packages: [InstalledPackageInfo]
        @Binding var selectedPackages: Set<String>
        @ObservedObject var viewState: PackageViewState // Receive viewState

        private let brewExecutablePath = BrewBarUtility.shared.brewPath ?? "/opt/homebrew/bin/brew" // Need brew path here too

        var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    // Installed Packages Table Header Row
                    HStack {
                        Text("Select")
                            .fontWeight(.bold)
                            .frame(width: 60, alignment: .leading)
                        Text("Package")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Version")
                            .fontWeight(.bold)
                            .frame(width: 100, alignment: .leading)
                        Text("Source")
                            .fontWeight(.bold)
                            .frame(width: 120, alignment: .leading)
                        Text("Actions")
                            .fontWeight(.bold)
                            .frame(width: 60, alignment: .center)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.2))

                    // Package Rows
                    ForEach(packages) { package in
                        HStack {
                            // Checkbox
                            Checkbox(isChecked: Binding(
                                get: { selectedPackages.contains(package.name) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedPackages.insert(package.name)
                                    } else {
                                        selectedPackages.remove(package.name)
                                    }
                                }
                            ))
                            .frame(width: 60, alignment: .leading)

                            // Package Name
                            Text(package.name)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Version
                            Text(package.version)
                                .foregroundColor(.secondary)
                                .frame(width: 100, alignment: .leading)

                            // Source
                            Text(package.source)
                                .foregroundColor(.secondary)
                                .frame(width: 120, alignment: .leading)

                            // Uninstall Button
                            Button(action: {
                                let isCask = package.source == "cask"
                                var args = ["uninstall"]
                                if isCask { args.append("--cask") }
                                args.append(package.name)
                                viewState.terminalArgs = args
                                viewState.terminalTitle = "Uninstalling \(package.name)..."
                                viewState.terminalKey = UUID()
                                viewState.isTerminalProcessRunning = true
                                viewState.showTerminalSheet = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .help("Uninstall \(package.name)")
                            .frame(width: 60, alignment: .center)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(selectedPackages.contains(package.name) ? Color.blue.opacity(0.1) : (packages.firstIndex(of: package)! % 2 == 0 ? Color.clear : Color.gray.opacity(0.05)))
                    }
                }
            }
        }
    }

    // MARK: - Alert Handling

    private func showCloseConfirmationAlert() {
        let alert = NSAlert()
        alert.messageText = "Task Still Running"
        alert.informativeText = "Closing this window will stop the current Homebrew task. Are you sure you want to close it?"
        alert.addButton(withTitle: "Close Anyway") // Destructive action
        alert.addButton(withTitle: "Cancel")       // Safe action
        alert.alertStyle = .warning

        // Present the alert modally
        let response = alert.runModal()

        if response == .alertFirstButtonReturn { // Corresponds to "Close Anyway"
            // User confirmed, close the sheet
            // Note: Closing the sheet/window should implicitly handle process termination
            // as observed in the AppDelegate's windowWillClose logic.
            viewState.showTerminalSheet = false
            // Explicitly mark as not running, although onProcessEnd should also do this.
            viewState.isTerminalProcessRunning = false
        }
        // If "Cancel" is clicked, do nothing.
    }
}

// Simple custom Checkbox
struct Checkbox: View {
    @Binding var isChecked: Bool

    var body: some View {
        Button(action: {
            isChecked.toggle()
        }) {
            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                .foregroundColor(isChecked ? .blue : .gray)
        }
        .buttonStyle(BorderlessButtonStyle())
    }
}
