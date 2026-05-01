import AppKit
import Foundation
import SwiftUI

// MARK: - User-facing enums

enum TerminalAppearanceMode: String, CaseIterable, Identifiable {
    case matchSystem
    case dark
    case light

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
            case .matchSystem: return "Match system"
            case .dark: return "Always dark"
            case .light: return "Always light"
        }
    }
}

enum TerminalColorPreset: String, CaseIterable, Identifiable {
    case catppuccin
    case systemAdaptive

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
            case .catppuccin: return "Catppuccin"
            case .systemAdaptive: return "System"
        }
    }

    func colors(for scheme: ColorScheme) -> (background: NSColor, foreground: NSColor) {
        switch self {
            case .catppuccin:
                let darkBackground = NSColor(red: 30 / 255, green: 30 / 255, blue: 46 / 255, alpha: 1)
                let darkForeground = NSColor(red: 205 / 255, green: 214 / 255, blue: 244 / 255, alpha: 1)
                let lightBackground = NSColor(red: 239 / 255, green: 241 / 255, blue: 245 / 255, alpha: 1)
                let lightForeground = NSColor(red: 76 / 255, green: 79 / 255, blue: 105 / 255, alpha: 1)
                if scheme == .dark {
                    return (darkBackground, darkForeground)
                }
                return (lightBackground, lightForeground)
            case .systemAdaptive:
                // Fixed sRGB pairs: dynamic `textBackgroundColor` / `textColor` still often resolve
                // against the *window* appearance, so “Always light” stayed dark inside SwiftTerm.
                return Self.systemLikeFixedColors(for: scheme)
        }
    }

    /// Neutral “system terminal” chrome independent of the hosting window appearance.
    private static func systemLikeFixedColors(for scheme: ColorScheme) -> (NSColor, NSColor) {
        if scheme == .dark {
            return (
                NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1),
                NSColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)
            )
        }
        return (
            NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 1)
        )
    }

    /// ANSI foreground for the “process completed” line.
    func exitMessageANSIPrefix(success: Bool, scheme: ColorScheme) -> String {
        switch self {
            case .catppuccin:
                if success {
                    return "\u{001B}[38;2;166;227;161m"
                }
                return "\u{001B}[38;2;243;139;168m"
            case .systemAdaptive:
                return success ? "\u{001B}[32m" : "\u{001B}[31m"
        }
    }

    /// SwiftUI colors for the settings preview (aligned with exit-message ANSI choices).
    func previewCompletionColors(for scheme: ColorScheme) -> (success: Color, failure: Color) {
        switch self {
            case .catppuccin:
                return (
                    Color(red: 166 / 255, green: 227 / 255, blue: 161 / 255),
                    Color(red: 243 / 255, green: 139 / 255, blue: 168 / 255)
                )
            case .systemAdaptive:
                return (
                    Color(red: 0.2, green: 0.78, blue: 0.35),
                    Color(red: 0.95, green: 0.26, blue: 0.21)
                )
        }
    }
}

// MARK: - Keys & resolution

enum TerminalPreferences {
    static let appearanceKey = "terminalAppearanceMode"
    static let presetKey = "terminalColorPreset"
}
