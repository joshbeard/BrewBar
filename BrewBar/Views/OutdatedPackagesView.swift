import Foundation
import SwiftUI
import Combine

// State container for the view
class PackageViewState: ObservableObject {
    @Published var isCheckingForUpdates: Bool = false
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
    @ObservedObject var viewState: PackageViewState

    let updateSinglePackage: (String) -> Void
    let updateSelectedPackages: ([String]) -> Void
    let updateAllPackages: () -> Void
    let uninstallPackage: (String) -> Void
    let uninstallSelectedPackages: ([String]) -> Void
    let checkNow: () -> Void

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

    init(packages: [PackageInfo],
         installed: [InstalledPackageInfo],
         errorOccurred: Bool = false,
         viewState: PackageViewState = PackageViewState(),
         updateSinglePackage: @escaping (String) -> Void,
         updateSelectedPackages: @escaping ([String]) -> Void,
         updateAllPackages: @escaping () -> Void,
         uninstallPackage: @escaping (String) -> Void,
         uninstallSelectedPackages: @escaping ([String]) -> Void,
         checkNow: @escaping () -> Void) {
        self.packagesInfo = packages
        self.installedPackages = installed
        self.errorOccurred = errorOccurred
        self.viewState = viewState
        self.updateSinglePackage = updateSinglePackage
        self.updateSelectedPackages = updateSelectedPackages
        self.updateAllPackages = updateAllPackages
        self.uninstallPackage = uninstallPackage
        self.uninstallSelectedPackages = uninstallSelectedPackages
        self.checkNow = checkNow
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
                    checkNow()
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
        .frame(minWidth: 650, minHeight: 350) // Ensure minimum size even when there's an error
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
                        viewState.isCheckingForUpdates = true
                        checkNow()
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
                            viewState.isCheckingForUpdates = true
                            checkNow()
                        }
                        .disabled(viewState.isCheckingForUpdates)

                        Button("Upgrade Selected") {
                            let packageNames = Array(selectedPackages)
                            if !packageNames.isEmpty {
                                updateSelectedPackages(packageNames)
                            }
                        }
                        .disabled(selectedPackages.isEmpty || viewState.isCheckingForUpdates)

                        Button("Upgrade All") {
                            updateAllPackages()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewState.isCheckingForUpdates)
                    }
                    .padding(.horizontal)

                    // Table of outdated packages
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
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
                                    .frame(width: 80, alignment: .leading)
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
                                    Text(package.source)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)
                                    HStack(spacing: 10) {
                                        Button(action: {
                                            updateSinglePackage(package.name)
                                        }) {
                                            Image(systemName: "arrow.up.circle")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .help("Upgrade \(package.name)")

                                        Button(action: {
                                            uninstallPackage(package.name)
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
                                uninstallSelectedPackages(Array(selectedInstalledPackages))
                            }
                        }
                        .disabled(selectedInstalledPackages.isEmpty)
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal)

                    // Table of installed packages
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
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
                                    .frame(width: 80, alignment: .leading)
                                Text("Actions")
                                    .fontWeight(.bold)
                                    .frame(width: 60, alignment: .center)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.2))

                            ForEach(filteredInstalledPackages) { package in
                                HStack {
                                    Checkbox(isChecked: Binding(
                                        get: { selectedInstalledPackages.contains(package.name) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedInstalledPackages.insert(package.name)
                                            } else {
                                                selectedInstalledPackages.remove(package.name)
                                            }
                                        }
                                    ))
                                    .frame(width: 60, alignment: .leading)

                                    Text(package.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(package.version)
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)

                                    Text(package.source)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Button(action: {
                                        uninstallPackage(package.name)
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
                                .background(selectedInstalledPackages.contains(package.name) ? Color.blue.opacity(0.1) : (filteredInstalledPackages.firstIndex(of: package)! % 2 == 0 ? Color.clear : Color.gray.opacity(0.05)))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
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