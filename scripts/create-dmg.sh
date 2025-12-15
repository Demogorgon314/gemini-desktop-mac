#!/bin/bash

# Create DMG for Gemini Desktop
# Usage: ./scripts/create-dmg.sh [APP_PATH] [OUTPUT_DIR]

set -e

APP_NAME="Gemini Desktop"
DEFAULT_APP_PATH="build/Build/Products/Release/${APP_NAME}.app"
DEFAULT_OUTPUT_DIR="build/artifacts"

APP_PATH="${1:-$DEFAULT_APP_PATH}"
OUTPUT_DIR="${2:-$DEFAULT_OUTPUT_DIR}"

# Ensure absolute paths
APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

DMG_FINAL="${OUTPUT_DIR}/GeminiDesktop.dmg"
VOLUME_NAME="Gemini Desktop"

echo "Creating DMG for ${APP_NAME}..."
echo "Source App: ${APP_PATH}"
echo "Output DMG: ${DMG_FINAL}"

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at ${APP_PATH}"
    echo "Please build the app first or provide correct path."
    exit 1
fi

# Create staging directory
STAGING_DIR="${OUTPUT_DIR}/dmg-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy app to staging
echo "Copying app..."
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create Applications symlink
ln -s /Applications "$STAGING_DIR/Applications"

# Remove old DMG if exists
rm -f "$DMG_FINAL"

# Create DMG directly (no mount needed)
echo "Creating DMG..."
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_FINAL"

# Cleanup staging
rm -rf "$STAGING_DIR"

echo ""
echo "✅ DMG created successfully: ${DMG_FINAL}"
echo "Size: $(du -h "$DMG_FINAL" | cut -f1)"
