#!/bin/bash
set -e
# Build DMG and create a GitHub Release with it.
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.1.2
# Requires: gh (brew install gh) and `gh auth login`

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_PATH="$REPO_DIR/build/Cropaway-${VERSION}.dmg"

cd "$REPO_DIR"
./scripts/build-dmg.sh "$VERSION"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH"
    exit 1
fi

echo "📤 Creating release v${VERSION} and uploading DMG..."
gh release create "v${VERSION}" "$DMG_PATH" --title "v${VERSION}" --generate-notes
echo "✅ Release v${VERSION} is live."
