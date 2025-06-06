# BrewBar

A simple menu bar app for macOS that monitors your Homebrew packages for
updates. It sits in your menu bar and checks for outdated packages on a schedule
you define.

> [!WARNING]
> **Early Development**
>
> This is a 0.x.x release under very active development from a maintainer with
> little Swift/SwiftUI experience.
>
> Beware that it will have bugs and it might not work.

## Features

- 🔍 Check for outdated Homebrew packages on a customizable schedule
- 🔔 Notifications when updates are available
- 🖱️ Selective package updates - choose which packages to upgrade
- 🚀 One-click updates for individual packages or all at once
- ⚙️ Customizable update intervals, including user-defined schedules
- 📋 Browse and remove installed packages
- 💻 Embedded terminal emulator using [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)

## Screenshots

<div align="center">
  <img src=".github/readme/optimized/1.png" alt="Main menu" width="400"/>
  <p><em>Main menu showing outdated packages</em></p>

  <img src=".github/readme/optimized/2.png" alt="Package details" width="400"/>
  <p><em>Package information and upgrade options</em></p>

  <img src=".github/readme/optimized/3.png" alt="Browse installed packages" width="400"/>
  <p><em>Browse and uninstall installed packages</em></p>

  <img src=".github/readme/optimized/4.png" alt="Running an upgrade" width="400"/>
  <p><em>Running an upgrade of all packages</em></p>

  <img src=".github/readme/optimized/5.png" alt="All packages are up to date" width="400"/>
  <p><em>All packages are up to date</em></p>
</div>

## Installation

```shell
brew tap joshbeard/brewbar
brew install --cask brewbar
```

Alternatively, you can download directly from [releases](https://github.com/joshbeard/BrewBar/releases).

**NOTE:** This is not notarized by Apple. You may need to run `xattr -d com.apple.quarantine /Applications/BrewBar.app` if you get a warning that the application is corrupted.

## License

[MIT License](LICENSE)
