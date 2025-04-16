# Changelog

All notable changes to BrewBar will be documented in this file.

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
