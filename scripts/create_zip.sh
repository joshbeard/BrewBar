#!/bin/bash
set -e

# BrewBar ZIP Creation Script
# This script creates a ZIP archive of the app

APP_PATH="$1"
ZIP_PATH="${2:-BrewBar.zip}"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: Please provide a valid app path"
    echo "Usage: $0 <app_path> [zip_path]"
    exit 1
fi

echo "Creating ZIP from $APP_PATH at $ZIP_PATH"

# Ensure output directory exists
mkdir -p "$(dirname "$ZIP_PATH")"

# Get the directory and file name
APP_DIR=$(dirname "$APP_PATH")
APP_NAME=$(basename "$APP_PATH")

# Create ZIP archive
echo "Creating ZIP archive..."
cd "$APP_DIR" && zip -r "$(cd "$(dirname "$ZIP_PATH")" && pwd)/$(basename "$ZIP_PATH")" "$APP_NAME"

# Verify the ZIP was created
if [ -f "$ZIP_PATH" ]; then
    echo "ZIP created successfully at $ZIP_PATH"
    echo "ZIP file size: $(du -h "$ZIP_PATH" | cut -f1)"
else
    echo "Error: Failed to create ZIP at $ZIP_PATH"
    exit 1
fi