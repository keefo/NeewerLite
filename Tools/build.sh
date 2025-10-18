#!/bin/bash

PRODUCT_NAME=NeewerLite
SIGNING_ID="Developer ID Application: Beyondcow Software (MJA89JYF67)"
BUILD_FOLDER="$(PWD)/build"

APP_PATH="$BUILD_FOLDER/$PRODUCT_NAME.xcarchive"
ZIP_PATH="$BUILD_FOLDER/$PRODUCT_NAME.zip"

echo $BUILD_FOLDER

#rm -rf build
mkdir build

# check version in info.plist against appcast.xml
INFO_PLIST="../NeewerLite/NeewerLite/Resources/Info.plist"

# Extract Sparkle appcast URL from Info.plist
APPCAST_URL=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$INFO_PLIST")

echo "Using appcast URL: $APPCAST_URL"
# Download or use local appcast.xml
if [[ "$APPCAST_URL" =~ ^http ]]; then
    curl -s -o appcast.xml "$APPCAST_URL"
    APPCAST="appcast.xml"
else
    APPCAST="$APPCAST_URL"
fi

# Extract versions from Info.plist
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
PLIST_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")

# Extract version from appcast.xml (assumes version is in sparkle:shortVersionString attribute)
# Extract sparkle:version from appcast.xml (for CFBundleVersion)
APPCAST_VERSION=$(grep -o 'sparkle:shortVersionString="[^"]*"' "$APPCAST" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
APPCAST_BUILD=$(grep -o 'sparkle:version="[^"]*"' "$APPCAST" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')

echo "Info.plist CFBundleShortVersionString: $PLIST_VERSION"
echo "Info.plist CFBundleVersion: $PLIST_BUILD"
echo "appcast.xml version: $APPCAST_VERSION"
echo "appcast.xml sparkle:version: $APPCAST_BUILD"

# If APPCAST_BUILD is not a number, default to 0
if ! [[ "$APPCAST_BUILD" =~ ^[0-9]+$ ]]; then
    APPCAST_BUILD=0
    echo "❌ appcast.xml sparkle:version is not a number, defaulting to 0."
    exit 1
fi

# Increment sparkle:version by 1 for new CFBundleVersion
# Update Info.plist
NEW_BUILD=$((APPCAST_BUILD + 1))
echo "Updating CFBundleVersion in Info.plist to $NEW_BUILD"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$INFO_PLIST"

# check version update
# Suggest next version by incrementing the patch number
IFS='.' read -r major minor patch <<< "$APPCAST_VERSION"
if [[ -z "$major" || -z "$minor" || -z "$patch" ]]; then
    # fallback if version is not in x.y.z format
    SUGGESTED_VERSION="$APPCAST_VERSION"
else
    patch=$((patch + 1))
    SUGGESTED_VERSION="$major.$minor.$patch"
fi

echo "Current appcast.xml version: $APPCAST_VERSION"
echo "Suggested next version: $SUGGESTED_VERSION"
read -p "Enter new CFBundleShortVersionString (or press Enter to use $SUGGESTED_VERSION): " NEW_VERSION

if [[ -z "$NEW_VERSION" ]]; then
    NEW_VERSION="$SUGGESTED_VERSION"
fi

echo "Updating CFBundleShortVersionString in Info.plist to $NEW_VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"

# Re-extract PLIST_VERSION for further checks
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
echo "Info.plist CFBundleShortVersionString (after update): $PLIST_VERSION"

rm appcast.xml

# build plugin
pushd ../NeewerLiteStreamDeck/
./build.sh
popd

# build app
pushd ../NeewerLite
xcodebuild -list -project NeewerLite.xcodeproj
# Skip SwiftLint run script by setting RUN_CLANG_STATIC_ANALYZER=NO for faster archive builds
# Note: SwiftLint warnings won't fail the build, but the script phase itself might
xcodebuild -scheme NeewerLite -configuration Release clean archive -archivePath $APP_PATH ENABLE_USER_SCRIPT_SANDBOXING=NO
XCODE_EXIT=$?
#xcrun altool -t osx -f build/Release/NeewerLite.xcarchive --primary-bundle-id com.beyondcow.neewerlite --output-format xml --notarize-app
popd

if [ $XCODE_EXIT -ne 0 ]; then
    echo "❌ Archive build failed with exit code $XCODE_EXIT"
    exit 1
fi

# Check if the app was actually created
if [ ! -d "$APP_PATH/Products/Applications/NeewerLite.app" ]; then
    echo "❌ Archive created but app not found at expected location"
    echo "Looking for archive contents..."
    find "$APP_PATH" -name "*.app" -type d 2>/dev/null || echo "No .app found in archive"
    exit 1
fi

mv ../NeewerLiteStreamDeck/neewerlite/com.beyondcow.neewerlite.streamDeckPlugin $APP_PATH/Products/Applications/NeewerLite.app/Contents/Resources/

ITEMS=""

FRAMEWORKS_DIR="$APP_PATH/Products/Applications/NeewerLite.app/Contents/Frameworks/"
if [ -d "$FRAMEWORKS_DIR" ] ; then
    FRAMEWORKS=$(find "${FRAMEWORKS_DIR}" -depth -type d -name "*.framework" -or -name "*.dylib" -or -name "*.bundle" | sed -e "s/\(.*framework\)/\1\/Versions\/A\//")
    RESULT=$?
    if [[ $RESULT != 0 ]] ; then
        exit 1
    fi

    ITEMS="${FRAMEWORKS}"
fi


echo "Found:"
echo "${ITEMS}"

echo 'codesigning...'

codesign --verbose --force --deep --options runtime --sign "$SIGNING_ID" --entitlements ../NeewerLite/NeewerLite/NeewerLite.entitlements $APP_PATH/Products/Applications/NeewerLite.app
codesign --verbose --force --deep --options runtime --sign "$SIGNING_ID" $APP_PATH/Products/Applications/NeewerLite.app/Contents/Frameworks/Sparkle.framework
codesign --verbose --force --deep --options runtime --sign "$SIGNING_ID" $APP_PATH/Products/Applications/NeewerLite.app/Contents/Frameworks/Sparkle.framework/Versions/A/Resources/Autoupdate.app

for ITEM in $ITEMS;
do
	echo "Signing '${ITEM}'"
    codesign --force --verbose --sign "${SIGNING_ID}" --entitlements "../NeewerLite/NeewerLite/Empty.entitlements" "${ITEM}"
    RESULT=$?
    if [[ $RESULT != 0 ]] ; then
        echo "Failed to sign '${ITEM}'."
        IFS=$SAVED_IFS
        exit 1
    fi
done

codesign -dvvvv $APP_PATH/Products/Applications/NeewerLite.app
codesign -d --entitlements :- $APP_PATH/Products/Applications/NeewerLite.app
codesign -vvv --deep --strict $APP_PATH/Products/Applications/NeewerLite.app

# Package the app and build appcast
echo "Package the app"

DMG_FILENAME=NeewerLite
BUILD_APP_DIR="./build/NeewerLite.xcarchive/Products/Applications"

# Install create-dmg if needed
brew list create-dmg &>/dev/null || brew install create-dmg

# Remove old DMG if exists
if [ -f ${DMG_FILENAME}.dmg ]; then
    rm -f ${DMG_FILENAME}.dmg
fi

# Create DMG
create-dmg --volname ${DMG_FILENAME} --background ../Design/background.jpg --volicon ../Design/icon_128x128@2x.icns --icon-size 64 --app-drop-link 130 128 --icon NeewerLite.app 350 128 ${DMG_FILENAME}.dmg "${BUILD_APP_DIR}/NeewerLite.app"

echo "Build App Cast"

# Create zip for appcast
/usr/bin/ditto -c -k --keepParent "${BUILD_APP_DIR}/NeewerLite.app" "${BUILD_APP_DIR}/NeewerLite.zip"

# Generate appcast
./generate_appcast "${BUILD_APP_DIR}/"

# Move DMG to build directory
mv NeewerLite.dmg ./build/NeewerLite.xcarchive/Products/Applications/

xcrun notarytool submit "./build/NeewerLite.xcarchive/Products/Applications/NeewerLite.dmg" --keychain-profile "AC_PASSWORD" --wait 
xcrun stapler staple ./build/NeewerLite.xcarchive/Products/Applications/NeewerLite.dmg
stapler validate ./build/NeewerLite.xcarchive/Products/Applications/NeewerLite.dmg

#
# xcrun notarytool submit "$ZIP_PATH" --keychain-profile "AC_PASSWORD" --wait 
# xcrun stapler staple  $APP_PATH/Products/Applications/NeewerLite.app
# stapler validate  $APP_PATH/Products/Applications/NeewerLite.app
# 
# xcrun notarytool info 51c277db-0710-4667-8525-83abcbcb23c5 --keychain-profile "AC_PASSWORD"
# xcrun notarytool log 51c277db-0710-4667-8525-83abcbcb23c5 --keychain-profile "AC_PASSWORD"
# 
