#!/bin/bash

# Build Gemini Desktop for macOS
# Usage: ./scripts/build.sh [--release|--debug] [--sign] [--arch <x86_64|arm64|universal>]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
CONFIGURATION="Release"
SIGN_APP=false
ARCH="x86_64" # Default arch, will change logic below

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
        --arch)
            ARCH="$2"
            shift
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--release|--debug] [--sign] [--arch <x86_64|arm64|universal>]"
            echo ""
            echo "Options:"
            echo "  --release    Build in Release configuration (default)"
            echo "  --debug      Build in Debug configuration"
            echo "  --sign       Enable code signing (requires provisioning profile)"
            echo "  --arch       Target architecture: x86_64, arm64, or universal (default: current)"
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
# Output dir includes arch to prevent overwrites
OUTPUT_DIR="${BUILD_DIR}/Build/Products/${CONFIGURATION}" 
APP_NAME="Gemini Desktop"

echo "========================================"
echo "Building ${PROJECT_NAME}"
echo "Configuration: ${CONFIGURATION}"
echo "Sign App: ${SIGN_APP}"
echo "Architecture: ${ARCH}"
echo "========================================"

cd "$PROJECT_DIR"

# Clean and build
echo ""
echo "🧹 Cleaning previous build..."
# Ideally we only clean for the current config/arch, but full clean is safer for now
# rm -rf "$BUILD_DIR" 

echo ""
echo "📦 Resolving package dependencies..."

# Construct build arguments
BUILD_ARGS=(
    -project "${PROJECT_NAME}.xcodeproj"
    -scheme "$SCHEME_NAME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$BUILD_DIR"
    -destination "platform=macOS"
)

if [ "$ARCH" == "universal" ]; then
    BUILD_ARGS+=("ARCHS=arm64 x86_64" "ONLY_ACTIVE_ARCH=NO")
elif [ "$ARCH" == "x86_64" ]; then
    BUILD_ARGS+=("ARCHS=x86_64" "ONLY_ACTIVE_ARCH=NO")
elif [ "$ARCH" == "arm64" ]; then
    BUILD_ARGS+=("ARCHS=arm64" "ONLY_ACTIVE_ARCH=NO")
fi

if [ "$SIGN_APP" = false ]; then
    echo ""
    echo "🔨 Building without code signing..."
    BUILD_ARGS+=(
        "CODE_SIGN_IDENTITY=-"
        "CODE_SIGNING_REQUIRED=NO"
        "CODE_SIGNING_ALLOWED=NO"
    )
else
    echo ""
    echo "🔨 Building with code signing..."
fi

xcodebuild build "${BUILD_ARGS[@]}"

# Check if build succeeded
APP_OUTPUT_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
if [ -d "$APP_OUTPUT_PATH" ]; then
    echo ""
    echo "✅ Build succeeded!"
    echo ""
    echo "📍 App location: ${APP_OUTPUT_PATH}"
    echo "📊 App size: $(du -sh "${APP_OUTPUT_PATH}" | cut -f1)"
    echo ""
    echo "To run the app:"
    echo "  open \"${APP_OUTPUT_PATH}\""
    echo ""
    echo "To create a DMG, run:"
    echo "  ./scripts/create-dmg.sh \"${APP_OUTPUT_PATH}\""
else
    echo ""
    echo "❌ Build failed: App not found at expected location: ${APP_OUTPUT_PATH}"
    exit 1
fi
