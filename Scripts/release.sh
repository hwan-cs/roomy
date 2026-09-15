#!/bin/bash

# Usage: Scripts/release.sh [--skip-notarize]
#   --skip-notarize   build, sign, and package a DMG without submitting
#                      for notarization (useful for a quick local test of
#                      the packaging step itself)
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="Roomy"
WORKSPACE="Roomy.xcworkspace"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/Roomy.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/Roomy.app"
DMG_PATH="$BUILD_DIR/Roomy.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-RoomyNotary}"
SKIP_NOTARIZE=false

for arg in "$@"; do
    if [ "$arg" = "--skip-notarize" ]; then
        SKIP_NOTARIZE=true
    fi
done

echo "==> Regenerating Xcode project"
tuist generate --no-open

echo "==> Archiving (Release)"
rm -rf "$BUILD_DIR"
xcodebuild -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Release \
    archive -archivePath "$ARCHIVE_PATH"

echo "==> Exporting for Developer ID distribution"
cat > "$BUILD_DIR/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Submitting for notarization (keychain profile: $NOTARY_PROFILE)"
    ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/Roomy-for-notarization.zip"
    xcrun notarytool submit "$BUILD_DIR/Roomy-for-notarization.zip" \
        --keychain-profile "$NOTARY_PROFILE" --wait

    echo "==> Stapling notarization ticket"
    xcrun stapler staple "$APP_PATH"
else
    echo "==> Skipping notarization (--skip-notarize)"
fi

echo "==> Packaging DMG"
STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "Roomy" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGING"

echo "==> Done: $DMG_PATH"
