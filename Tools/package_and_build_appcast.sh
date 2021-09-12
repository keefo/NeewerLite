#!/bin/bash

BUILD_DIR="$1"

DMG_FILENAME=NeewerLite

echo "Package the app"

brew install create-dmg

if [ -f ${DMG_FILENAME}.dmg ];
then
rm -f ${DMG_FILENAME}.dmg
fi

create-dmg --volname ${DMG_FILENAME} --background ../Design/background.jpg --volicon ../Design/icon_128x128@2x.icns --icon-size 64 --app-drop-link 130 128 --icon NeewerLite.app 350 128 ${DMG_FILENAME}.dmg  "${BUILD_DIR}/NeewerLite.app"

echo "Build App Cast"

/usr/bin/ditto -c -k --keepParent "${BUILD_DIR}/NeewerLite.app" "${BUILD_DIR}/NeewerLite.zip"

./generate_appcast "${BUILD_DIR}/"

