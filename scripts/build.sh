#!/bin/bash
set -e

# BrewBar Build Script
# This script builds the app and injects version information from git
#
# Usage:
#   ./scripts/build.sh                      # Build with auto-detected version
#   ./scripts/build.sh 1.2.3                # Build with specific version
#   ./scripts/build.sh --info               # Show current app version info

# Function to get the latest git tag version
get_git_tag_version() {
    local tag=$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || echo "")
    echo "$tag"
}

# Function to get commit count for build number
get_commit_count() {
    git rev-list --count HEAD 2>/dev/null || echo "1"
}

# Function to show current app version
show_app_version() {
    local app_path="$1"
    echo "App version information:"
    if [ -f "$app_path/Contents/Info.plist" ]; then
        echo "Version: $(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app_path/Contents/Info.plist")"
        echo "Build: $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app_path/Contents/Info.plist")"
        /usr/libexec/PlistBuddy -c "Print :BuildDate" "$app_path/Contents/Info.plist" 2>/dev/null && echo "Build Date: $(/usr/libexec/PlistBuddy -c "Print :BuildDate" "$app_path/Contents/Info.plist")" || echo "Build Date: Not set"
    else
        echo "Error: Info.plist not found at $app_path/Contents/Info.plist"
    fi
}

find_codesign_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1
}

# Function to update version in an existing app
update_app_version() {
    echo "Error: --update is no longer supported because editing Info.plist after signing invalidates the app bundle."
    echo "Rebuild instead: $0 <version>"
    exit 1
}

# Move to project root directory
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)
APP_PATH="${PROJECT_ROOT}/BrewBar.app"
BUILD_DATE=$(date "+%Y-%m-%d %H:%M:%S")
BUILD_NUMBER=$(get_commit_count)

# Check command options
if [ "$1" = "--update" ]; then
    # Update existing app without rebuilding
    if [ -z "$2" ]; then
        echo "Error: Version argument is required for update"
        echo "Usage: $0 --update <version>"
        exit 1
    fi
    update_app_version
    exit 0
elif [ "$1" = "--info" ]; then
    # Show current app version
    if [ ! -d "$APP_PATH" ]; then
        echo "No BrewBar.app found in project root."
        exit 1
    fi
    show_app_version "$APP_PATH"
    exit 0
else
    # Set version for build
    if [ -n "$1" ]; then
        VERSION="$1"
        echo "Using custom version: $VERSION"
    else
        # Extract version information from git
        if git describe --tags --exact-match 2>/dev/null; then
            # We're on a tag - use it as the version
            VERSION=$(git describe --tags --exact-match)
            # Remove 'v' prefix if present
            VERSION=${VERSION#v}
        else
            # Not on a tag - use a development version with commit hash
            BRANCH=$(git rev-parse --abbrev-ref HEAD)
            COMMIT_HASH=$(git rev-parse --short HEAD)
            VERSION="dev-${BRANCH}-${COMMIT_HASH}"
        fi
    fi
fi

echo "Building BrewBar"
echo "Version: $VERSION"
echo "Build: $BUILD_NUMBER"
echo "Date: $BUILD_DATE"
echo
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-$(find_codesign_identity)}"
if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing mode: Apple Development ($SIGNING_IDENTITY)"
else
    SIGNING_IDENTITY="-"
    echo "Signing mode: ad hoc (no Apple Development identity found; local notifications may be unavailable)"
fi

# Build the app
echo "Building with xcodebuild..."
xcodebuild -project "${PROJECT_ROOT}/BrewBar.xcodeproj" \
    -scheme BrewBar \
    -configuration Release \
    -derivedDataPath "${PROJECT_ROOT}/build" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    BUILD_DATE="$BUILD_DATE" \
    clean build

# Copy the app to the current directory
echo "Copying built app to ./BrewBar.app"
rm -rf "${PROJECT_ROOT}/BrewBar.app"
cp -R "${PROJECT_ROOT}/build/Build/Products/Release/BrewBar.app" "${PROJECT_ROOT}/"

echo "Build complete!"
show_app_version "$APP_PATH"
