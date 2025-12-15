#!/bin/bash

# Build Gemini Desktop for macOS
# Usage: ./scripts/build.sh [--release|--debug] [--sign]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
CONFIGURATION="Release"
SIGN_APP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            CONFIGURATION="Debug"
            shift
            ;;
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --sign)
            SIGN_APP=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--release|--debug] [--sign]"
            echo ""
            echo "Options:"
            echo "  --release    Build in Release configuration (default)"
            echo "  --debug      Build in Debug configuration"
            echo "  --sign       Enable code signing (requires provisioning profile)"
            echo "  -h, --help   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

PROJECT_NAME="GeminiDesktop"
SCHEME_NAME="GeminiDesktop"
BUILD_DIR="${PROJECT_DIR}/build"
OUTPUT_DIR="${BUILD_DIR}/Build/Products/${CONFIGURATION}"
APP_NAME="Gemini Desktop"

echo "========================================"
echo "Building ${PROJECT_NAME}"
echo "Configuration: ${CONFIGURATION}"
echo "Sign App: ${SIGN_APP}"
echo "========================================"

cd "$PROJECT_DIR"

# Clean and build
echo ""
echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"

echo ""
echo "📦 Resolving package dependencies..."

# Build command with or without signing
if [ "$SIGN_APP" = true ]; then
    echo ""
    echo "🔨 Building with code signing..."
    xcodebuild \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$BUILD_DIR" \
        -destination "platform=macOS" \
        build
else
    echo ""
    echo "🔨 Building without code signing..."
    xcodebuild \
        -project "${PROJECT_NAME}.xcodeproj" \
        -scheme "$SCHEME_NAME" \
        -configuration "$CONFIGURATION" \
        -derivedDataPath "$BUILD_DIR" \
        -destination "platform=macOS" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        build
fi

# Check if build succeeded
if [ -d "${OUTPUT_DIR}/${APP_NAME}.app" ]; then
    echo ""
    echo "✅ Build succeeded!"
    echo ""
    echo "📍 App location: ${OUTPUT_DIR}/${APP_NAME}.app"
    echo "📊 App size: $(du -sh "${OUTPUT_DIR}/${APP_NAME}.app" | cut -f1)"
    echo ""
    echo "To run the app:"
    echo "  open \"${OUTPUT_DIR}/${APP_NAME}.app\""
    echo ""
    echo "To copy to Applications:"
    echo "  cp -R \"${OUTPUT_DIR}/${APP_NAME}.app\" /Applications/"
    echo ""
    echo "To create a DMG, run:"
    echo "  ./scripts/create-dmg.sh"
else
    echo ""
    echo "❌ Build failed: App not found at expected location"
    exit 1
fi
