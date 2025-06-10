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

# 1. Verify environment variables
if [ -z "$NEEWERLITE_REMOTE_FOLDER" ]
then
      echo "\$NEEWERLITE_REMOTE_FOLDER is empty"
      exit 1
fi

if [ -z "$NEEWERLITE_REMOTE_USER_NAME" ]
then
      echo "\$NEEWERLITE_REMOTE_USER_NAME is empty"
      exit 1
fi

# 2. Extract version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist")
TAG_NAME="v$VERSION"
RELEASE_TITLE="$TAG_NAME"

echo "Publishing release: $RELEASE_TITLE"
echo "Using tag: $TAG_NAME"

# 3. Replace download path in appcast
echo 'replace download path'
sed -i '' -e "s/NeewerLite.zip/download\/NeewerLite.zip/" "${BUILD_DIR}/appcast.xml"

# 4. Upload to your website
echo "Uploading appcast to $NEEWERLITE_REMOTE_USER_NAME:$NEEWERLITE_REMOTE_FOLDER..."
ssh $NEEWERLITE_REMOTE_USER_NAME "rm $NEEWERLITE_REMOTE_FOLDER/appcast.xml"
scp "${BUILD_DIR}/appcast.xml" $NEEWERLITE_REMOTE_USER_NAME:$NEEWERLITE_REMOTE_FOLDER/
scp "${ZIP_PATH}" $NEEWERLITE_REMOTE_USER_NAME:$NEEWERLITE_REMOTE_FOLDER/download/

# 5. Upload to GitHub release
echo "Creating GitHub release for $TAG_NAME..."

gh release create "$TAG_NAME" "$ZIP_PATH" \
  --repo "keefo/NeewerLite" \
  --title "$RELEASE_TITLE" \
  --notes "Auto-generated release for $RELEASE_TITLE"

echo "✅ Release $TAG_NAME published to GitHub and website."