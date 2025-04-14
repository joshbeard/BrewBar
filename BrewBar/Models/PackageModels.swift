import Foundation
import SwiftUI

// MARK: - Package Info Structure
struct PackageInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let currentVersion: String
    let availableVersion: String
    let source: String  // Will contain tap or cask info
    var isSelected: Bool = false

    // To support Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: PackageInfo, rhs: PackageInfo) -> Bool {
        return lhs.name == rhs.name
    }
}

// MARK: - Installed Package Info Structure
struct InstalledPackageInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let version: String
    let source: String  // Will contain tap or cask info
    var isSelected: Bool = false

    // To support Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: InstalledPackageInfo, rhs: InstalledPackageInfo) -> Bool {
        return lhs.name == rhs.name
    }
}