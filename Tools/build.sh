#!/bin/bash

PRODUCT_NAME=NeewerLite
SIGNING_ID="Developer ID Application: Beyondcow Software (MJA89JYF67)"
BUILD_FOLDER="$(PWD)/build"

APP_PATH="$BUILD_FOLDER/$PRODUCT_NAME.xcarchive"
ZIP_PATH="$BUILD_FOLDER/$PRODUCT_NAME.zip"

echo $BUILD_FOLDER

#rm -rf build
mkdir build

pushd ../NeewerLite

xcodebuild -list -project NeewerLite.xcodeproj
xcodebuild -scheme NeewerLite build -configuration Release clean -archivePath $APP_PATH archive

#xcrun altool -t osx -f build/Release/NeewerLite.xcarchive --primary-bundle-id com.beyondcow.neewerlite --output-format xml --notarize-app

popd


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

./package_and_build_appcast.sh ./build/NeewerLite.xcarchive/Products/Applications/

xcrun notarytool submit "NeewerLite.dmg" --keychain-profile "AC_PASSWORD" --wait 
xcrun stapler staple NeewerLite.dmg
stapler validate NeewerLite.dmg

#
# xcrun notarytool submit "$ZIP_PATH" --keychain-profile "AC_PASSWORD" --wait 
# xcrun stapler staple  $APP_PATH/Products/Applications/NeewerLite.app
# stapler validate  $APP_PATH/Products/Applications/NeewerLite.app
# 
# xcrun notarytool info 51c277db-0710-4667-8525-83abcbcb23c5 --keychain-profile "AC_PASSWORD"
# xcrun notarytool log 51c277db-0710-4667-8525-83abcbcb23c5 --keychain-profile "AC_PASSWORD"
# 
# 
