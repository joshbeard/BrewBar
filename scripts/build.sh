#!/bin/bash
set -e

# BrewBar Build Script
# This script builds the app and injects version information from git
#
# Usage:
#   ./scripts/build.sh                      # Build with auto-detected version
#   ./scripts/build.sh 1.2.3                # Build with specific version
#   ./scripts/build.sh --update 1.2.3       # Update version in existing app without rebuilding
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

# Function to update version in an existing app
update_app_version() {
    local version="$1"
    local build_number="$2"
    local build_date="$3"
    local app_path="$4"

    if [ ! -d "$app_path" ]; then
        echo "Error: App not found at $app_path"
        exit 1
    fi

    local info_plist="$app_path/Contents/Info.plist"

    if [ ! -f "$info_plist" ]; then
        echo "Error: Info.plist not found at $info_plist"
        exit 1
    fi

    echo "Updating version information in $app_path"
    echo "Version: $version"
    echo "Build: $build_number"
    echo "Date: $build_date"

    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$info_plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$info_plist"
    /usr/libexec/PlistBuddy -c "Add :BuildDate string $build_date" "$info_plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :BuildDate $build_date" "$info_plist"

    echo "Version updated successfully!"
    show_app_version "$app_path"
    echo "To see the change, quit the app (if running) and relaunch it."
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
    VERSION="$2"
    update_app_version "$VERSION" "$BUILD_NUMBER" "$BUILD_DATE" "$APP_PATH"
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

# Create a temporary Info.plist with the version information
TEMP_INFO_PLIST=$(mktemp)
cp "${PROJECT_ROOT}/BrewBar/Info.plist" "$TEMP_INFO_PLIST"

# Update the plist with version information
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$TEMP_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$TEMP_INFO_PLIST"
/usr/libexec/PlistBuddy -c "Add :BuildDate string $BUILD_DATE" "$TEMP_INFO_PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :BuildDate $BUILD_DATE" "$TEMP_INFO_PLIST"

# Build the app
echo "Building with xcodebuild..."
xcodebuild -project "${PROJECT_ROOT}/BrewBar.xcodeproj" \
    -scheme BrewBar \
    -configuration Release \
    -derivedDataPath "${PROJECT_ROOT}/build" \
    clean build

# Since Xcode is set to generate its own Info.plist, we need to overwrite it after the build
echo "Injecting version information into built app..."
BUILT_APP_PLIST="${PROJECT_ROOT}/build/Build/Products/Release/BrewBar.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUILT_APP_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$BUILT_APP_PLIST"
/usr/libexec/PlistBuddy -c "Add :BuildDate string $BUILD_DATE" "$BUILT_APP_PLIST" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :BuildDate $BUILD_DATE" "$BUILT_APP_PLIST"

# Cleanup temp file
rm "$TEMP_INFO_PLIST"

# Copy the app to the current directory
echo "Copying built app to ./BrewBar.app"
cp -R "${PROJECT_ROOT}/build/Build/Products/Release/BrewBar.app" "${PROJECT_ROOT}/"

echo "Build complete!"
show_app_version "$APP_PATH"
