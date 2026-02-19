#!/bin/bash
set -e
# Create a version tag and push it to trigger the unified release workflow.
# CI builds both macOS DMG (macos-26 runner) and Windows installer,
# then publishes a single GitHub Release with all artifacts.
#
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.2.0

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
TAG="v${VERSION}"

# Ensure we're on main and up to date
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
    echo "⚠️  You're on '$BRANCH', not 'main'. Switch to main first."
    exit 1
fi

git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)
if [ "$LOCAL" != "$REMOTE" ]; then
    echo "⚠️  Local main is not up to date with origin. Run: git pull origin main"
    exit 1
fi

# Check tag doesn't already exist
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ Tag $TAG already exists."
    exit 1
fi

echo "🏷️  Creating tag $TAG on main..."
git tag -a "$TAG" -m "Release $VERSION"

echo "📤 Pushing tag to origin..."
git push origin "$TAG"

echo ""
echo "✅ Tag $TAG pushed. GitHub Actions will now:"
echo "   1. Build macOS DMG (macos-26 runner, Xcode 26)"
echo "   2. Build Windows installer + portable ZIP (windows-latest)"
echo "   3. Create unified GitHub Release with all artifacts"
echo ""
echo "   Track progress: gh run watch"
