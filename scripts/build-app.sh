#!/bin/bash
# Builds dist/SlideSnap.app (and dist/SlideSnap.zip for a release) from the Swift package.
# Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.0}"
APP=dist/SlideSnap.app

# Universal (Apple silicon + Intel) needs full Xcode; otherwise build for this Mac only.
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN=.build/apple/Products/Release
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/SlideSnapApp" "$APP/Contents/MacOS/SlideSnap"
# Not next to it: MacOS/slidesnap and MacOS/SlideSnap are one file on a case-insensitive disk.
cp "$BIN/slidesnap" "$APP/Contents/Helpers/slidesnap"

# Icon
TMP="$(mktemp -d)"
swift scripts/make-icon.swift "$TMP/icon.png"
mkdir "$TMP/SlideSnap.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$TMP/SlideSnap.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$TMP/icon.png" --out "$TMP/SlideSnap.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/SlideSnap.iconset" -o "$APP/Contents/Resources/SlideSnap.icns"
cp "$TMP/icon.png" dist/icon.png
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SlideSnap</string>
  <key>CFBundleDisplayName</key><string>SlideSnap</string>
  <key>CFBundleIdentifier</key><string>io.github.flutescorpio.slidesnap</string>
  <key>CFBundleExecutable</key><string>SlideSnap</string>
  <key>CFBundleIconFile</key><string>SlideSnap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Slide photos</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.jpeg</string><string>public.heic</string><string>public.png</string>
        <string>com.adobe.pdf</string><string>public.folder</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally; downloaded copies need right-click → Open once.
codesign --force --deep --sign - "$APP"

(cd dist && rm -f SlideSnap.zip && ditto -c -k --keepParent SlideSnap.app SlideSnap.zip)
echo "built $APP ($VERSION)"
