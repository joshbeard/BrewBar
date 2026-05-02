# Changelog

All notable changes to BrewBar will be documented in this file.

## 1.0.0 - 2026-05-02

### Added

- **Settings window** (macOS Settings / Preferences): update-check interval and custom intervals, login item and notification toggles, editable default `brew update` / `brew upgrade` argument lists, and a **Terminal** tab for embedded-terminal appearance (match system, always light, or always dark) and color preset (**Catppuccin** or **System** neutral chrome) with a live preview.
- **Package info sheet** on both **Outdated** and **Installed** tabs: tap the package name or the info icon to run `brew info` / `brew info --cask` and view output with basic formatting (section headers, links, emphasized labels).
- **Confirmation** before uninstalling (single package, **Uninstall Selected**, and outdated list); **Uninstall Selected** now removes every selected package in one `brew uninstall` command (with correct `--cask` placement per row).
- **About BrewBar** using the standard About panel: copyright line, credits with a clickable GitHub link, and a menu-bar item to open it when the app menu is available.
- **Dock icon** when Settings (or the packages window) is shown: the app temporarily promotes to a regular activation policy and calls `unhide` so the Dock tile appears, then returns to menu-bar-only when all such windows are closed.
- **`BrewBarApp` + `AppState`**: SwiftUI `@main` entry, observable app state, and a slimmer `AppDelegate` focused on lifecycle and window callbacks.
- **Test notification** button plus notification diagnostics in Settings.

### Changed

- **Packages window** is built with **SwiftUI** (`OutdatedPackagesView` + `NSHostingController`); legacy window controllers and `MenuBarManager` are removed.
- **Menu bar** content is SwiftUI-driven from shared `AppState` (status text, intervals, actions, **Settings** link, **About**, GitHub link, quit).
- **Embedded terminal** (`SwiftTerm`): theme follows Settings; completion line is written before the process-end handler so messages still render when the view dismisses.
- After a **successful `brew update`** (exact match to your configured update command), the inline terminal **closes automatically** and returns to the package list.
- **Alerts** for “task still running” (leaving the terminal or closing the packages window) use **SwiftUI** `.alert` instead of `NSAlert`.
- **Optimistic list updates** after uninstall now drop **all** package names from the uninstall argv, not only the first.
- **Timer scheduling** for background checks is anchored from the last run to reduce drift after sleep/wake.
- **Local build and release signing** now injects version metadata before Xcode signs the app, verifies signed bundles instead of re-signing them, and avoids generated broad entitlements.
- **Notification delivery** uses a single modern `UserNotifications` path with `@MainActor`, async authorization, foreground presentation, and no launch-time permission prompt.

### Removed

- `main.swift` / `ContentView` entry path, `MenuBarManager`, `WindowControllers`, **CrashReporter**, and the unused app entitlements file.

### Fixed

- **System** terminal preset respects **Always light** / **Always dark** by using fixed light/dark chrome and setting `NSAppearance` on the terminal view, instead of following only the window’s dark chrome.
- **Compiler / SwiftUI**: split the outdated-packages tab into smaller view builders to avoid type-check timeouts in Release builds.
- **Update notifications** now compare the actual outdated package/version set instead of only the package count, so same-count update changes still notify.
- **Notification permission failures** caused by invalid/ad hoc local builds were traced to signing and build-script behavior; generated `BrewBar.app` bundles now keep valid sealed resources.

## 0.0.19 - 2025-04-18

- confirmation when closing a running process
- improve relative time display for "next update" in menu item

## 0.0.18 - 2025-04-17

- prompt for restart when upgraded

## 0.0.17 - 2025-04-17

- another brew cask fix

## 0.0.16 - 2025-04-17

- yet another brew cask fix

## 0.0.15 - 2025-04-17

- ci updates

## 0.0.14 - 2025-04-17

- another brew cask fix

## 0.0.13 - 2025-04-17

- feature: log rotation

## 0.0.12 - 2025-04-17

- attempt fix for brew cask behavior

## 0.0.11 - 2025-04-17

- fix: refresh outdated packages table after update

## 0.0.10 - 2025-04-16

- Refactored package table view

## 0.0.9 - 2025-04-16

- Use [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for an embedded terminal emulator for running Homewbrew commands
- Misc UI tweaks

## 0.0.8 - 2025-04-14

### Changed

- All user-initiated Homebrew commands now run in dedicated Terminal windows for better visibility and interaction
- Automatic background update checks remain silent and non-interactive
- Package lists (both installed and outdated) now automatically refresh after operations complete

## 0.0.7 - 2025-04-14

- Test release

## 0.0.6 - 2025-04-14

- Removed `auto_update` from Cask - handle upgrades directly via Homebrew

## 0.0.5 - 2025-04-14

### Fixed

- Fixed deployment target compatibility by updating MACOSX_DEPLOYMENT_TARGET to 14.0 (Sonoma)

## 0.0.4 - 2025-04-13

### Improved

- Enhanced source detection for outdated packages with more reliable detection
- Widened source column for better visibility of tap names
- Added fallback mechanism for packages not found in installed inventory
- Improved error handling for brew info commands

## 0.0.3 - 2025-04-13

### Fixed

- Source column now properly displays in the outdated packages view

## 0.0.2 - 2025-04-13

### Fixed

- Fixed icon for available updates

## 0.0.1 - 2025-04-13

### Added

- Initial release of BrewBar

