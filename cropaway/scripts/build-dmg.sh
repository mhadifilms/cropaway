#!/bin/bash
set -e

# Build and package Cropaway as DMG
# Usage: ./scripts/build-dmg.sh [version]

VERSION="${1:-1.0.0}"
APP_NAME="Cropaway"
SCHEME="cropaway"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/${DMG_NAME}"

echo "🔨 Building ${APP_NAME} v${VERSION}..."

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build release
xcodebuild -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    archive \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

# Export archive
xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
    -exportPath "$BUILD_DIR/Release" \
    -exportOptionsPlist "$PROJECT_DIR/scripts/export-options.plist" \
    2>/dev/null || {
    # If export fails, copy from archive directly
    echo "📦 Extracting from archive..."
    cp -R "$BUILD_DIR/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "$BUILD_DIR/Release/"
}

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed: ${APP_PATH} not found"
    exit 1
fi

echo "📀 Creating DMG..."

# Create DMG staging directory
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"

# Create symbolic link to Applications
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up
rm -rf "$DMG_DIR"

echo "✅ DMG created: $DMG_PATH"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"

# Output for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
    echo "dmg_path=$DMG_PATH" >> "$GITHUB_OUTPUT"
    echo "dmg_name=$DMG_NAME" >> "$GITHUB_OUTPUT"
fi
