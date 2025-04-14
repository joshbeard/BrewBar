#!/bin/bash
set -e

# BrewBar Homebrew Tap Update Script
# This script pushes the Homebrew formula to the tap repository

VERSION="$1"
FORMULA_PATH="$2"
TAP_REPO=${TAP_REPO:-"joshbeard/homebrew-brewbar"}
GITHUB_TOKEN=${GITHUB_TOKEN:-$TAP_GITHUB_TOKEN}

# Debug information
echo "Debug info for tap update:"
echo "  VERSION=$VERSION"
echo "  FORMULA_PATH=$FORMULA_PATH"
echo "  TAP_REPO=$TAP_REPO"
echo "  GITHUB_TOKEN isset: $([ -n "$GITHUB_TOKEN" ] && echo "yes" || echo "no")"
echo "  Current directory: $(pwd)"

if [ -z "$VERSION" ]; then
    echo "Error: Version is required"
    echo "Usage: $0 <version> <formula_path>"
    exit 1
fi

if [ -z "$FORMULA_PATH" ]; then
    echo "Error: Formula path is required"
    echo "Usage: $0 <version> <formula_path>"
    exit 1
fi

# Try to find formula file
if [ ! -f "$FORMULA_PATH" ]; then
    echo "Warning: Formula file not found at specified path: $FORMULA_PATH"
    # Try to find it in the current directory
    if [ -f "$(basename "$FORMULA_PATH")" ]; then
        FORMULA_PATH="$(basename "$FORMULA_PATH")"
        echo "Using formula file from current directory: $FORMULA_PATH"
    else
        echo "Error: Could not find formula file"
        echo "Files in current directory:"
        ls -la
        exit 1
    fi
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "Error: GITHUB_TOKEN or TAP_GITHUB_TOKEN environment variable is required"
    exit 1
fi

echo "Updating Homebrew tap with BrewBar $VERSION"

# Set up temporary directory
TEMP_DIR=$(mktemp -d)
echo "Using temporary directory: $TEMP_DIR"

# Set up git
git config --global user.name "GitHub Action"
git config --global user.email "github-actions@github.com"

# Clone the tap repository
echo "Cloning tap repository..."
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${TAP_REPO}.git" "$TEMP_DIR"

# Create Casks directory if it doesn't exist
mkdir -p "$TEMP_DIR/Casks"

# Verify formula file content
echo "Formula file content:"
cat "$FORMULA_PATH"

# Copy the formula to the Casks directory
echo "Copying formula to Casks directory..."
cp "$FORMULA_PATH" "$TEMP_DIR/Casks/brewbar.rb"

# Commit and push
echo "Committing and pushing changes..."
cd "$TEMP_DIR"
git add Casks/brewbar.rb
git commit -m "Update brewbar to ${VERSION}"
git push

# Clean up
echo "Cleaning up..."
rm -rf "$TEMP_DIR"

echo "Homebrew tap updated successfully!"