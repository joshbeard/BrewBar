#!/bin/bash
set -e

# BrewBar DMG Creation Script
# This script creates a DMG installer for the app

APP_PATH="$1"
DMG_PATH="${2:-BrewBar.dmg}"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: Please provide a valid app path"
    echo "Usage: $0 <app_path> [dmg_path]"
    exit 1
fi

echo "Creating DMG from $APP_PATH at $DMG_PATH"

# Create a temporary directory for mounting
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Copy the app to the temporary directory
echo "Copying app to temporary directory..."
cp -r "$APP_PATH" "$TEMP_DIR/"

# Create a symlink to Applications folder
echo "Creating Applications symlink..."
ln -s /Applications "$TEMP_DIR/"

# Create a README file with instructions
echo "Creating README.txt..."
cat > "$TEMP_DIR/README.txt" << EOF
If you get a "damaged app" warning:

Option 1: Right-click the app and choose "Open" from the context menu
Option 2: Run this in Terminal: xattr -cr /Applications/BrewBar.app

For more information, visit: https://github.com/joshbeard/BrewBar
EOF

# Create DMG using hdiutil
echo "Creating DMG..."
hdiutil create -volname "BrewBar" -srcfolder "$TEMP_DIR" -ov -format UDZO "$DMG_PATH"

# Clean up
echo "Cleaning up temporary directory..."
rm -rf "$TEMP_DIR"

echo "DMG created successfully at $DMG_PATH"