import Foundation
import SwiftUI

/// Line-oriented styling for `brew info` / `brew info --cask` plain-text output.
enum BrewInfoFormatting {
    private static let mono = Font.system(.body, design: .monospaced)
    private static let monoSemibold = Font.system(.body, design: .monospaced).weight(.semibold)

    /// Builds an attributed string with section headers, links, emphasized labels, and monospace body.
    static func attributedString(from raw: String) -> AttributedString {
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output = AttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                output.append(AttributedString("\n"))
            }
            output.append(styleLine(line))
        }
        return output
    }

    private static func styleLine(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return AttributedString("")
        }

        // brew section headers (check before key:value — lines like "==> foo: stable …" contain ":")
        if trimmed.hasPrefix("==>") {
            var a = AttributedString(line)
            a.font = monoSemibold
            a.foregroundColor = Color.accentColor
            return a
        }

        if trimmed.hasPrefix("Exit status ") {
            var a = AttributedString(line)
            a.font = monoSemibold
            a.foregroundColor = Color.secondary
            return a
        }

        // Whole line is a URL
        if looksLikeURL(trimmed), let url = URL(string: trimmed) {
            var a = AttributedString(line)
            a.font = mono
            a.link = url
            return a
        }

        // Indented continuation (options text, caveats)
        if line.first == "\t" {
            var a = AttributedString(line)
            a.font = mono
            a.foregroundColor = Color.primary
            return a
        }

        // Indented code / paths (e.g. "  set rtp+=…", "  https://…")
        if line.hasPrefix("  ") {
            let rest = String(line.dropFirst(2))
            if looksLikeURL(rest.trimmingCharacters(in: .whitespaces)),
               let url = URL(string: rest.trimmingCharacters(in: .whitespaces))
            {
                var prefix = AttributedString("  ")
                prefix.font = mono
                var linkPart = AttributedString(rest.trimmingCharacters(in: .whitespaces))
                linkPart.font = mono
                linkPart.link = url
                return prefix + linkPart
            }
            var a = AttributedString(line)
            a.font = mono
            a.foregroundColor = Color.primary
            return a
        }

        // "Label: value" (License:, From:, Build:, install:, etc.) — key is a single identifier
        if let parsed = parseKeyValueLine(line) {
            var keyPart = AttributedString(parsed.key + ": ")
            keyPart.font = monoSemibold
            keyPart.foregroundColor = Color.primary

            let valueTrimmed = parsed.value.trimmingCharacters(in: .whitespaces)
            if looksLikeURL(valueTrimmed), let url = URL(string: valueTrimmed) {
                var v = AttributedString(valueTrimmed)
                v.font = mono
                v.link = url
                return keyPart + v
            }
            var v = AttributedString(parsed.value)
            v.font = mono
            v.foregroundColor = Color.primary
            return keyPart + v
        }

        var plain = AttributedString(line)
        plain.font = mono
        plain.foregroundColor = Color.primary
        return plain
    }

    private struct KeyValue {
        let key: String
        let value: String
    }

    /// `^([\w\-]+):\s*(.*)$` — avoids matching "To do something, see:" (spaces in pseudo-key).
    private static func parseKeyValueLine(_ line: String) -> KeyValue? {
        guard let match = line.wholeMatch(of: /^([\w\-]+):\s*(.*)$/) else { return nil }
        return KeyValue(key: String(match.1), value: String(match.2))
    }

    private static func looksLikeURL(_ s: String) -> Bool {
        s.hasPrefix("http://") || s.hasPrefix("https://")
    }
}
