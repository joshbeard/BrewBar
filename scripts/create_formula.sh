#!/bin/bash
set -e

# BrewBar Homebrew Formula Creation Script
# This script creates a Homebrew cask formula for the app

VERSION="$1"
ZIP_PATH="$2"
FORMULA_PATH="${3:-brewbar.rb}"
REPO=${GITHUB_REPOSITORY:-"joshbeard/BrewBar"}

# Debug information
echo "Debug: Creating formula with:"
echo "  VERSION=$VERSION"
echo "  ZIP_PATH=$ZIP_PATH"
echo "  FORMULA_PATH=$FORMULA_PATH"
echo "  REPO=$REPO"

# Validate inputs
if [ -z "$VERSION" ]; then
    echo "Error: Version is required"
    echo "Usage: $0 <version> <zip_path> [formula_path]"
    exit 1
fi

if [ -z "$ZIP_PATH" ]; then
    echo "Error: ZIP path is required"
    echo "Usage: $0 <version> <zip_path> [formula_path]"
    exit 1
fi

if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: ZIP file not found at: $ZIP_PATH"
    echo "Current directory: $(pwd)"
    echo "Contents of directory: $(ls -la $(dirname "$ZIP_PATH"))"
    exit 1
fi

echo "Creating Homebrew formula for BrewBar $VERSION"

# Calculate SHA256 checksum
echo "Calculating SHA256 checksum..."
SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
echo "SHA256: $SHA256"

# Create formula file
echo "Creating formula at $FORMULA_PATH..."
mkdir -p "$(dirname "$FORMULA_PATH")"

cat > "$FORMULA_PATH" << EOF
cask "brewbar" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${REPO}/releases/download/v#{version}/BrewBar.zip"
  name "BrewBar"
  desc "A menubar app for managing Homebrew packages"
  homepage "https://github.com/${REPO}"

  app "BrewBar.app"

  # Ensure permissions before uninstall
  uninstall_preflight do
    if File.exist?("#{appdir}/BrewBar.app")
      system_command "chown", args: ["-R", "#{ENV['USER']}:admin", "#{appdir}/BrewBar.app"]
      system_command "chmod", args: ["-R", "u+rw", "#{appdir}/BrewBar.app"]
    end
  end

  # Ensure permissions before install
  preflight do
    system_command "chown", args: ["#{ENV['USER']}:admin", "#{appdir}"]
    system_command "chmod", args: ["u+rw", "#{appdir}"]
  end

  # Remove quarantine attribute
  postflight do
    system_command "xattr", args: ["-d", "com.apple.quarantine", "#{appdir}/BrewBar.app"]
  rescue
    nil
  end

  uninstall quit:      "me.joshbeard.BrewBar",
            launchctl: "me.joshbeard.BrewBar",
            delete:    "#{appdir}/BrewBar.app"

  zap trash: [
    "~/Library/Application Support/BrewBar",
    "~/Library/Preferences/me.joshbeard.BrewBar.plist",
    "~/Library/Caches/me.joshbeard.BrewBar",
    "~/Library/Logs/BrewBar",
    "~/Library/Saved Application State/me.joshbeard.BrewBar.savedState"
  ]
end
EOF

echo "Homebrew formula created successfully at $FORMULA_PATH"