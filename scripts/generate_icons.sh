#!/bin/bash

# Move to project root directory
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

# Set paths
SOURCE_ICON="${PROJECT_ROOT}/BrewBar/Assets.xcassets/AppIcon.appiconset/icon.png"
OUTPUT_DIR="${PROJECT_ROOT}/BrewBar/Assets.xcassets/AppIcon.appiconset"

# Check if source icon exists
if [ ! -f "$SOURCE_ICON" ]; then
    echo "Source icon not found: $SOURCE_ICON"
    exit 1
fi

# Generate all required icon sizes
echo "Generating icon sizes..."
sips -z 16 16 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-16.png"
sips -z 32 32 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-32.png"
sips -z 64 64 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-64.png"
sips -z 128 128 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-128.png"
sips -z 256 256 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-256.png"
sips -z 512 512 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-512.png"
sips -z 1024 1024 "$SOURCE_ICON" --out "$OUTPUT_DIR/AppIcon-1024.png"

echo "App icons generated successfully!"