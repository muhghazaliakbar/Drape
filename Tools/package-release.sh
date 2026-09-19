#!/bin/bash
#
# Builds Drape for release and packages it as a DMG.
#
#   Tools/package-release.sh [output-directory]
#
# The app is ad-hoc signed (the project sets CODE_SIGN_IDENTITY "-"), not signed
# with a Developer ID and not notarised, so Gatekeeper will ask the person who
# downloads it to approve the app once. The README says how.
#
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-dist}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

VERSION="$(
  xcodebuild -project Drape.xcodeproj -scheme Drape \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk '/ MARKETING_VERSION = /{print $3}' | head -1
)"
: "${VERSION:?could not read MARKETING_VERSION from the project}"

echo "==> Building Drape $VERSION (universal)"
xcodebuild build \
  -project Drape.xcodeproj \
  -scheme Drape \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  | grep -E '^\*\*|error:|warning:' || true

APP="$BUILD_DIR/Build/Products/Release/Drape.app"
[ -d "$APP" ] || { echo "build produced no app bundle at $APP" >&2; exit 1; }

echo "==> Verifying the bundle"
# The tests are built into a PlugIns folder when the test scheme has run; a
# release build must not ship them.
rm -rf "$APP/Contents/PlugIns"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Drape"

echo "==> Staging the disk image"
STAGE="$BUILD_DIR/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/Drape-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "Drape $VERSION" \
  -srcfolder "$STAGE" \
  -format UDZO \
  -quiet \
  "$DMG"

shasum -a 256 "$DMG" | awk '{print $1"  "substr($2, match($2, /[^\/]*$/))}' > "$DMG.sha256"

echo
echo "==> $DMG"
cat "$DMG.sha256"
