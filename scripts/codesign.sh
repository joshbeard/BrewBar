#!/bin/bash
set -e

# BrewBar Codesign Script
# This script generates entitlements and codesigns the app

APP_PATH="$1"
IDENTITY=${CODE_SIGN_IDENTITY:-"-"} # Default to ad-hoc signing

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Error: Please provide a valid app path"
    echo "Usage: $0 <app_path>"
    exit 1
fi

echo "Codesigning $APP_PATH with identity: $IDENTITY"

# Create entitlements file if it doesn't exist
if [ ! -f "entitlements.plist" ]; then
    echo "Creating entitlements.plist..."
    cat > entitlements.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
EOF
fi

# Perform codesigning
echo "Codesigning with entitlements..."
codesign --force --deep --sign "$IDENTITY" --entitlements entitlements.plist "$APP_PATH"

echo "Verifying signature..."
codesign --verify --verbose "$APP_PATH"

echo "Codesigning complete!"