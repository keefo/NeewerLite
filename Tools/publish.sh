#!/bin/bash

# GitHub release metadata
REPO_OWNER="keefo"
REPO_NAME="NeewerLite"
TAG_NAME="v$(date +%Y.%m.%d.%H%M)"
RELEASE_NAME="Release $TAG_NAME"
RELEASE_BODY="Auto release uploaded by publish script."

BUILD_DIR="./build/NeewerLite.xcarchive/Products/Applications/"
DMG_FILENAME=NeewerLite
APP_PATH="${BUILD_DIR}/${DMG_FILENAME}.app"
ZIP_PATH="${BUILD_DIR}/${DMG_FILENAME}.zip"
DMG_PATH="${BUILD_DIR}/${DMG_FILENAME}.dmg"

# 1. Verify gh CLI is available
if ! command -v gh &>/dev/null; then
    echo "❌ gh CLI not found. Install with: brew install gh"
    exit 1
fi

# 2. Extract version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
TAG_NAME="v$VERSION"
RELEASE_TITLE="$TAG_NAME"

echo "Publishing release: $RELEASE_TITLE"
echo "Using tag: $TAG_NAME"

# 3. Fix download URL in appcast — point to GitHub release asset
echo 'Updating download URL in appcast.xml'
RELEASE_ZIP_URL="https://github.com/keefo/NeewerLite/releases/download/${TAG_NAME}/NeewerLite.zip"
sed -i '' -E "s|url=\"[^\"]*NeewerLite\.zip\"|url=\"${RELEASE_ZIP_URL}\"|" "${BUILD_DIR}/appcast.xml"

# 4. Ask before uploading the appcast

echo "appcast.xml"
cat "${BUILD_DIR}/appcast.xml"

echo "Github release tag:"
echo "$TAG_NAME"

echo "Github release title:"
echo "$RELEASE_TITLE"

echo "Files:"
sha256 "${ZIP_PATH}"
sha256 "${DMG_PATH}"

read -p "Are you sure you want to publish this release? [y/N] " answer
if [[ ! $answer =~ ^[Yy]$ ]]; then
    echo "Aborting publish."
    exit 1
fi

# Prompt for a release note
read -p "Enter release notes: " releaseNotes

# 4. Commit updated appcast.xml to repo (serves via raw.githubusercontent.com)
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Updating appcast.xml in repo..."
cp "${BUILD_DIR}/appcast.xml" "${REPO_ROOT}/appcast.xml"
pushd "${REPO_ROOT}" > /dev/null
git add appcast.xml
git commit -m "chore: update appcast.xml for ${TAG_NAME}"
git push
popd > /dev/null
echo "✅ appcast.xml pushed to GitHub."

# 5. Create GitHub release and upload DMG + ZIP
echo "Creating GitHub release for $TAG_NAME..."
gh release create "$TAG_NAME" \
  --repo "keefo/NeewerLite" \
  --title "$RELEASE_TITLE" \
  --notes $'Auto-generated release for '"$RELEASE_TITLE"$'\n'"$releaseNotes" \
  "$ZIP_PATH" \
  "$DMG_PATH"

echo "✅ Release $TAG_NAME published to GitHub."
echo ""

./validate.sh
