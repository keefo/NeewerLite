#!/bin/bash

# GitHub release metadata
REPO_OWNER="keefo"
REPO_NAME="NeewerLite"

BUILD_DIR="./build/NeewerLite.xcarchive/Products/Applications/"
DMG_FILENAME=NeewerLite
APP_PATH="${BUILD_DIR}/${DMG_FILENAME}.app"
ZIP_PATH="${BUILD_DIR}/${DMG_FILENAME}.zip"
DMG_PATH="${BUILD_DIR}/${DMG_FILENAME}.dmg"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 1. Verify prerequisites
if ! command -v gh &>/dev/null; then
    echo "❌ gh CLI not found. Install with: brew install gh"
    exit 1
fi

if [ ! -d "$APP_PATH" ]; then
    echo "❌ App not found at $APP_PATH. Run build.sh first."
    exit 1
fi

# 2. Extract version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist")
TAG_NAME="v$VERSION"
RELEASE_TITLE="$TAG_NAME"

echo "Publishing release: $RELEASE_TITLE (build $BUILD)"
echo "Using tag: $TAG_NAME"

# 3. Check that local main is up to date with remote
pushd "${REPO_ROOT}" > /dev/null
git fetch origin
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_HEAD=$(git rev-parse origin/main)
if [ "$LOCAL_HEAD" != "$REMOTE_HEAD" ]; then
    echo "⚠️  Local main ($LOCAL_HEAD) differs from origin/main ($REMOTE_HEAD)."
    echo "   Run 'git pull --rebase' or 'git rebase origin/main' first."
    read -p "Continue anyway? [y/N] " diverge_answer
    if [[ ! $diverge_answer =~ ^[Yy]$ ]]; then
        popd > /dev/null
        echo "Aborting publish."
        exit 1
    fi
fi
popd > /dev/null

# 4. Fix download URL in appcast — point to GitHub release asset
echo 'Updating download URL in appcast.xml'
RELEASE_ZIP_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${TAG_NAME}/NeewerLite.zip"
sed -i '' -E "s|url=\"[^\"]*NeewerLite\.zip\"|url=\"${RELEASE_ZIP_URL}\"|" "${BUILD_DIR}/appcast.xml"

# 5. Show summary and confirm
echo ""
echo "===== appcast.xml ====="
cat "${BUILD_DIR}/appcast.xml"
echo ""
echo "===== Release Info ====="
echo "Tag:   $TAG_NAME"
echo "Title: $RELEASE_TITLE"
echo ""
echo "===== Files ====="
sha256 "${ZIP_PATH}"
sha256 "${DMG_PATH}"
echo ""

read -p "Are you sure you want to publish this release? [y/N] " answer
if [[ ! $answer =~ ^[Yy]$ ]]; then
    echo "Aborting publish."
    exit 1
fi

# Prompt for a release note
read -p "Enter release notes: " releaseNotes

# 6. Commit and push appcast.xml + Info.plist FIRST (must succeed before creating release)
echo ""
echo "Pushing appcast.xml and Info.plist to main branch..."
cp "${BUILD_DIR}/appcast.xml" "${REPO_ROOT}/appcast.xml"
pushd "${REPO_ROOT}" > /dev/null
git add appcast.xml NeewerLite/NeewerLite/Resources/Info.plist
git commit -m "chore: update appcast.xml and Info.plist for ${TAG_NAME}"
if ! git push; then
    echo "❌ git push failed. Changes were NOT pushed to GitHub."
    echo "   Fix the issue (e.g. git pull --rebase) and re-run publish.sh."
    echo "   The release was NOT created."
    popd > /dev/null
    exit 1
fi
popd > /dev/null
echo "✅ appcast.xml and Info.plist pushed to GitHub."

# 7. Verify the remote appcast is correct before creating the release
echo "Verifying remote appcast.xml..."
sleep 2  # wait for GitHub raw CDN
REMOTE_APPCAST_VERSION=$(curl -sf "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main/appcast.xml" | grep -o 'sparkle:shortVersionString="[^"]*"' | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
if [ "$REMOTE_APPCAST_VERSION" != "$VERSION" ]; then
    echo "⚠️  Remote appcast shows version '$REMOTE_APPCAST_VERSION' (expected '$VERSION')."
    echo "   This may be a CDN cache delay (max-age=300). Proceeding anyway."
fi

# 8. Create GitHub release and upload DMG + ZIP
#    If a release with the same tag exists, delete it first
echo "Creating GitHub release for $TAG_NAME..."
if gh release view "$TAG_NAME" --repo "${REPO_OWNER}/${REPO_NAME}" &>/dev/null; then
    echo "⚠️  Release $TAG_NAME already exists."
    read -p "Overwrite existing release? [y/N] " overwrite_answer
    if [[ ! $overwrite_answer =~ ^[Yy]$ ]]; then
        echo "Aborting publish."
        exit 1
    fi
    gh release delete "$TAG_NAME" --repo "${REPO_OWNER}/${REPO_NAME}" --yes
    git push origin --delete "$TAG_NAME" 2>/dev/null || true
    git tag -d "$TAG_NAME" 2>/dev/null || true
    echo "✅ Old release $TAG_NAME deleted."
fi

if ! gh release create "$TAG_NAME" \
  --repo "${REPO_OWNER}/${REPO_NAME}" \
  --title "$RELEASE_TITLE" \
  --notes $'Auto-generated release for '"$RELEASE_TITLE"$'\n'"$releaseNotes" \
  "$ZIP_PATH" \
  "$DMG_PATH"; then
    echo "❌ Failed to create GitHub release."
    exit 1
fi

echo "✅ Release $TAG_NAME published to GitHub."
echo ""

./validate.sh
