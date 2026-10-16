#!/bin/sh
# Builds build/ToonRepeater.app (universal: Apple Silicon + Intel).
#   ./build.sh            build the app
#   ./build.sh --release  also create build/ToonRepeater.app.zip (used by the in-app updater) and
#                         build/ToonRepeater.dmg (drag-to-Applications installer) to attach to a GitHub release
set -eu

VERSION="${VERSION:-1.2}"
BUILD_NUMBER="${BUILD_NUMBER:-3}"
BUNDLE_ID="io.github.sidebandcoder.ToonRepeater"
# GitHub "owner/repo" whose releases the in-app updater uses; leave empty to disable updates.
UPDATE_REPOSITORY="SidebandCoder/ToonRepeater"
# TelemetryDeck app ID for opt-in anonymous analytics; leave empty to build without analytics.
TELEMETRYDECK_APP_ID="9A23F3CE-1354-4C8B-B142-EA22D27343BA"
# Code-signing certificate in your keychain. A stable identity keeps macOS's Accessibility permission
# across rebuilds; without one the app is signed ad-hoc and the permission must be re-granted each build.
SIGN_IDENTITY="${SIGN_IDENTITY:-MultiController Local Signing}"

cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64

APP="build/ToonRepeater.app"
rm -rf "$APP" "build/ToonRepeater.app.zip" "build/ToonRepeater.dmg"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/apple/Products/Release/ToonRepeater" "$APP/Contents/MacOS/ToonRepeater"

# App icon: Resources/AppIcon.png (1024×1024, on Apple's icon grid) -> AppIcon.icns
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ToonRepeater</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>ToonRepeater</string>
    <key>CFBundleDisplayName</key><string>ToonRepeater</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 SidebandCoder. MIT License.</string>
    <key>NSAppleEventsUsageDescription</key><string>ToonRepeater sends key events to your Toontown windows.</string>
    <key>MCUpdateRepository</key><string>${UPDATE_REPOSITORY}</string>
    <key>TelemetryDeckAppID</key><string>${TELEMETRYDECK_APP_ID}</string>
</dict>
</plist>
PLIST

if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
    echo "note: '$SIGN_IDENTITY' certificate not found; signing ad-hoc" >&2
    codesign --force --sign - "$APP"
fi
echo "Built $APP"

if [ "${1:-}" = "--release" ]; then
    ditto -c -k --keepParent "$APP" "build/ToonRepeater.app.zip"

    # Disk image with the app next to an Applications shortcut, for drag-to-install.
    STAGING="build/dmg-staging"
    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    ditto "$APP" "$STAGING/ToonRepeater.app"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "ToonRepeater ${VERSION}" -srcfolder "$STAGING" -fs HFS+ -format UDZO \
        -ov "build/ToonRepeater.dmg" >/dev/null
    rm -rf "$STAGING"
    if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
        codesign --force --sign "$SIGN_IDENTITY" "build/ToonRepeater.dmg"
    fi

    echo "Created build/ToonRepeater.app.zip and build/ToonRepeater.dmg — attach both to a GitHub release tagged v${VERSION}."
fi
