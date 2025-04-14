# BrewBar Makefile
#
# This Makefile coordinates the build and release process for BrewBar.
# It serves as both a local development tool and is used by CI.

.PHONY: all clean build version app dmg zip formula release

# Default version derived from git if not specified
VERSION ?= $(shell if [ -x scripts/get_version.sh ]; then scripts/get_version.sh; else echo "dev-unknown"; fi)
BUILT_APP = BrewBar.app
DIST_DIR = ./dist

all: build

# Show current version information
version:
	@echo "Version: $(VERSION)"
	@if [ -d "$(BUILT_APP)" ]; then \
		scripts/build.sh --info 2>/dev/null || echo "Could not retrieve app info"; \
	else \
		echo "No app built yet"; \
	fi

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf build $(BUILT_APP) $(DIST_DIR)
	@rm -f BrewBar.zip BrewBar.dmg
	@rm -f entitlements.plist brewbar.rb

# Build the app with specified or auto-detected version
build:
	@echo "Building BrewBar with version $(VERSION)..."
	@scripts/build.sh "$(VERSION)"

# Create signed app using entitlements
app: build
	@echo "Signing app..."
	@scripts/codesign.sh $(BUILT_APP)

# Create DMG installer
dmg: app
	@echo "Creating DMG..."
	@mkdir -p $(DIST_DIR)
	@scripts/create_dmg.sh $(BUILT_APP) $(DIST_DIR)/BrewBar.dmg

# Create ZIP archive
zip: app
	@echo "Creating ZIP archive..."
	@mkdir -p $(DIST_DIR)
	@scripts/create_zip.sh $(BUILT_APP) $(DIST_DIR)/BrewBar.zip

# Generate Homebrew formula (cask)
formula: zip
	@echo "Generating Homebrew formula..."
	@if echo "$(VERSION)" | grep -q "^dev-"; then \
		echo "Skipping Homebrew formula for development version: $(VERSION)"; \
		mkdir -p $(DIST_DIR); \
		echo "# Development version - not intended for Homebrew" > $(DIST_DIR)/brewbar.rb; \
		echo "# Version: $(VERSION)" >> $(DIST_DIR)/brewbar.rb; \
		echo "# Date: $$(date)" >> $(DIST_DIR)/brewbar.rb; \
	else \
		ZIP_PATH="$(shell pwd)/$(DIST_DIR)/BrewBar.zip"; \
		if [ ! -f "$$ZIP_PATH" ]; then \
			echo "Error: ZIP file not found at $$ZIP_PATH"; \
			exit 1; \
		fi; \
		echo "Using version: $(VERSION)"; \
		echo "Using ZIP: $$ZIP_PATH"; \
		scripts/create_formula.sh "$(VERSION)" "$$ZIP_PATH" "$(DIST_DIR)/brewbar.rb"; \
	fi

# Build everything for release
release: dmg zip formula
	@echo "Release artifacts created in $(DIST_DIR):"
	@ls -la $(DIST_DIR)

# Update the Homebrew tap repository
# Note: This requires GITHUB_TOKEN or TAP_GITHUB_TOKEN environment variable
update-tap: formula
	@echo "Updating Homebrew tap..."
	@if echo "$(VERSION)" | grep -q "^dev-"; then \
		echo "Skipping Homebrew tap update for development version: $(VERSION)"; \
	else \
		scripts/update_tap.sh "$(VERSION)" "$(DIST_DIR)/brewbar.rb"; \
	fi