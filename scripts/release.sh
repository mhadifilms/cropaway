#!/bin/bash
set -e
# Unified release script for Cropaway (macOS + Windows).
#
# 1. Builds the macOS DMG locally (requires Xcode 26 for Liquid Glass)
# 2. Tags and pushes to trigger Windows CI build
# 3. Waits for CI to create the GitHub Release with Windows artifacts
# 4. Uploads the macOS DMG to the same release
#
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.2.0

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
TAG="v${VERSION}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DMG_PATH="$REPO_DIR/build/Cropaway-${VERSION}.dmg"

cd "$REPO_DIR"

# ── Preflight checks ────────────────────────────────────────────────

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

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ Tag $TAG already exists."
    exit 1
fi

# ── Step 1: Build macOS DMG locally ─────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Step 1/4: Building macOS DMG locally"
echo "═══════════════════════════════════════════════════════════════"
./scripts/build-dmg.sh "$VERSION"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found: $DMG_PATH"
    exit 1
fi
echo "✅ macOS DMG ready: $DMG_PATH"

# ── Step 2: Tag and push ────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Step 2/4: Creating tag $TAG and pushing"
echo "═══════════════════════════════════════════════════════════════"
git tag -a "$TAG" -m "Release $VERSION"
git push origin "$TAG"
echo "✅ Tag $TAG pushed — Windows CI triggered"

# ── Step 3: Wait for CI to create the release ───────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Step 3/4: Waiting for Windows CI to finish..."
echo "═══════════════════════════════════════════════════════════════"

# Wait for the release workflow run to appear and complete
sleep 10
RUN_ID=$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
    echo "⚠️  Could not find release workflow run. Waiting longer..."
    sleep 20
    RUN_ID=$(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
fi

if [ -n "$RUN_ID" ]; then
    echo "   Watching run $RUN_ID..."
    gh run watch "$RUN_ID" --exit-status || {
        echo "❌ Windows CI failed. Check: gh run view $RUN_ID --log-failed"
        echo "   You can still upload the DMG manually:"
        echo "   gh release upload $TAG $DMG_PATH"
        exit 1
    }
    echo "✅ Windows CI complete — release created with Windows artifacts"
else
    echo "⚠️  Could not find CI run. Waiting 5 minutes then uploading DMG..."
    sleep 300
fi

# ── Step 4: Upload macOS DMG to the release ─────────────────────────

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Step 4/4: Uploading macOS DMG to release $TAG"
echo "═══════════════════════════════════════════════════════════════"

# Wait for the release to be fully created
sleep 5
gh release upload "$TAG" "$DMG_PATH" --clobber
echo "✅ macOS DMG uploaded to release $TAG"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  🎉 Release $TAG is live!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "  Release page: $(gh release view "$TAG" --json url --jq '.url')"
echo ""
echo "  Assets:"
gh release view "$TAG" --json assets --jq '.assets[].name' | sed 's/^/    - /'
