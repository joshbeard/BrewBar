#!/bin/bash
set -e

# BrewBar Codesign Script
# Verifies the app signature by default. It only re-signs when CODE_SIGN_IDENTITY is explicitly provided.

APP_PATH="$1"
MODE="${2:---verify-only}"
IDENTITY=${CODE_SIGN_IDENTITY:-}

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: Please provide a valid app path"
    echo "Usage: $0 <app_path> [--verify-only|--sign]"
    exit 1
fi

if [ "$MODE" = "--sign" ]; then
    if [ -z "$IDENTITY" ]; then
        echo "Error: CODE_SIGN_IDENTITY must be set when using --sign"
        exit 1
    fi
    echo "Codesigning $APP_PATH with identity: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" "$APP_PATH"
fi

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

echo "Codesign verification complete!"
