#!/bin/bash
set -e

# Extract version from git or environment
# Returns version in format X.Y.Z

# If APP_VERSION environment variable is set, use it
if [ -n "$APP_VERSION" ]; then
    echo "$APP_VERSION"
    exit 0
fi

# Try to get version from git tag
if git describe --tags --exact-match 2>/dev/null; then
    # We're on a tag - use it as the version
    VERSION=$(git describe --tags --exact-match)
    # Remove 'v' prefix if present
    VERSION=${VERSION#v}
    echo "$VERSION"
    exit 0
fi

# Not on a tag - use a development version
BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_HASH=$(git rev-parse --short HEAD)
echo "dev-${BRANCH}-${COMMIT_HASH}"