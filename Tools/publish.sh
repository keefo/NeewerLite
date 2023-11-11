#!/bin/bash

BUILD_DIR="./build/NeewerLite.xcarchive/Products/Applications/"
DMG_FILENAME=NeewerLite

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

echo 'replace download path'

sed -i '' -e "s/NeewerLite.zip/download\/NeewerLite.zip/" "${BUILD_DIR}/appcast.xml"

echo "Upload the appcast"

ssh $NEEWERLITE_REMOTE_USER_NAME "rm $NEEWERLITE_REMOTE_FOLDER/appcast.xml"

scp "${BUILD_DIR}/appcast.xml" $NEEWERLITE_REMOTE_USER_NAME:$NEEWERLITE_REMOTE_FOLDER/
scp "${BUILD_DIR}/${DMG_FILENAME}.zip" $NEEWERLITE_REMOTE_USER_NAME:$NEEWERLITE_REMOTE_FOLDER/download/
