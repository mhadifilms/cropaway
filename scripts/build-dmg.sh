#!/bin/bash
set -euo pipefail

# Build and package Cropaway as DMG.
# Usage: ./scripts/build-dmg.sh [version]
#
# Signing & notarization are OPTIONAL:
#   - If CODE_SIGN_IDENTITY and DEVELOPMENT_TEAM are set, the app/DMG are signed
#     with that Developer ID identity.
#   - If APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD are also set, the
#     DMG is submitted to Apple notary service and stapled.
#   - If those variables are not set, the build falls back to an ad-hoc signed
#     local build (suitable for personal use; Gatekeeper will warn on first
#     launch — right-click → Open to bypass).

VERSION="${1:-1.0.0}"
APP_NAME="Cropaway"
SCHEME="Cropaway"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
APP_PATH="$BUILD_DIR/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/${DMG_NAME}"

SIGN_RELEASE=false
NOTARIZE_RELEASE=false
if [ -n "${CODE_SIGN_IDENTITY:-}" ] && [ -n "${DEVELOPMENT_TEAM:-}" ]; then
    SIGN_RELEASE=true
    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]; then
        NOTARIZE_RELEASE=true
    fi
fi

if $SIGN_RELEASE; then
    echo "🔨 Building ${APP_NAME} v${VERSION} (signed: ${CODE_SIGN_IDENTITY})..."
else
    echo "🔨 Building ${APP_NAME} v${VERSION} (ad-hoc / unsigned)..."
    echo "    Set CODE_SIGN_IDENTITY + DEVELOPMENT_TEAM to produce a Developer-ID-signed build."
fi

python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if $SIGN_RELEASE; then
    xcodebuild -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
        archive \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
        DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
        ENABLE_HARDENED_RUNTIME=YES \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        MARKETING_VERSION="$VERSION"
else
    xcodebuild -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        -archivePath "$BUILD_DIR/${APP_NAME}.xcarchive" \
        archive \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        MARKETING_VERSION="$VERSION"
fi

mkdir -p "$BUILD_DIR/Release"
cp -R "$BUILD_DIR/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app" "$BUILD_DIR/Release/"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build failed: ${APP_PATH} not found"
    exit 1
fi

if $SIGN_RELEASE; then
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    codesign -dv --verbose=2 "$APP_PATH"
else
    codesign --force --deep --sign - "$APP_PATH"
fi

echo "📀 Creating DMG..."

mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

if $SIGN_RELEASE; then
    codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

if $NOTARIZE_RELEASE; then
    echo "📤 Submitting to Apple notary service..."
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH" || true
else
    echo "ℹ️  Skipping notarization (Apple credentials not provided)."
fi

python3 -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$DMG_DIR"

echo "✅ DMG created: $DMG_PATH"
echo "   Size: $(du -h "$DMG_PATH" | cut -f1)"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "dmg_path=$DMG_PATH" >> "$GITHUB_OUTPUT"
    echo "dmg_name=$DMG_NAME" >> "$GITHUB_OUTPUT"
fi
