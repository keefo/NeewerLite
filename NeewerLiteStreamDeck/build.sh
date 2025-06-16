#!/usr/bin/env bash

# Resolve the directory the script resides in (even if symlinked)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# update version
PLIST_PATH="$SCRIPT_DIR/../NeewerLite/NeewerLite/Resources/Info.plist"
SP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :SDPluginVersion" "$PLIST_PATH")
MANIFEST_JSON="$SCRIPT_DIR/neewerlite/com.beyondcow.neewerlite.sdPlugin/manifest.json"
jq --arg v "$SP_VERSION" '.Version = $v' "$MANIFEST_JSON" > "${MANIFEST_JSON}.tmp" && mv "${MANIFEST_JSON}.tmp" "$MANIFEST_JSON"

pushd neewerlite
npm run build
rm com.beyondcow.neewerlite.streamDeckPlugin
rm -rf com.beyondcow.neewerlite.sdPlugin/logs
streamdeck validate com.beyondcow.neewerlite.sdPlugin
streamdeck pack com.beyondcow.neewerlite.sdPlugin
popd
