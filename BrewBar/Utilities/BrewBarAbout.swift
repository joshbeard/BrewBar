import AppKit

enum BrewBarAbout {
    /// Standard system About panel with copyright and clickable GitHub link in Credits.
    static func presentStandardPanel() {
        let url = URL(string: "https://github.com/joshbeard/BrewBar")!
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(string: "Visit the project on GitHub:\n", attributes: [
            .font: font,
            .paragraphStyle: paragraph,
        ])
        credits.append(NSAttributedString(string: "github.com/joshbeard/BrewBar", attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .link: url,
        ]))

        // `AboutPanelOptionKey` has no `.copyright`; the system key is the string "Copyright".
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © 2026 Josh Beard",
            .credits: credits,
        ])
    }
}
