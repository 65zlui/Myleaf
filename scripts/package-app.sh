#!/usr/bin/env bash
#
# Builds a universal, ad-hoc signed release of myleaf and packages it as an
# .app, a DMG, and a ZIP under dist/.
#
# The project lives inside a FileProvider-synced folder on some machines;
# Finder metadata there breaks codesign, so the build runs in a temp dir and
# the bundle is signed explicitly after clearing extended attributes.
#
# Usage: ./scripts/package-app.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="$(grep -m1 'MARKETING_VERSION = ' myleaf.xcodeproj/project.pbxproj \
    | sed -E 's/.*= ([^;]+);/\1/' | tr -d '[:space:]')"
DIST_DIR="$ROOT/dist"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/myleaf-build.XXXXXX")"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/myleaf-stage.XXXXXX")"
APP="$BUILD_DIR/Build/Products/Release/myleaf.app"

cleanup() { rm -rf "$BUILD_DIR" "$STAGE"; }
trap cleanup EXIT

echo "==> Building myleaf $VERSION"
mkdir -p "$DIST_DIR"

xcodebuild \
    -project myleaf.xcodeproj \
    -scheme myleaf \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    build

if [[ ! -d "$APP" ]]; then
    echo "error: build did not produce $APP" >&2
    exit 1
fi

echo "==> Signing (ad-hoc, hardened runtime)"
xattr -cr "$APP"
codesign --force --sign - --options runtime \
    --entitlements "$ROOT/myleaf/myleaf.entitlements" \
    "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=2 "$APP" 2>&1 | grep -E 'Identifier|Format|Signature|Runtime'

echo "==> Packaging"
cp -R "$APP" "$STAGE/myleaf.app"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST_DIR/myleaf-$VERSION.dmg"
ZIP="$DIST_DIR/myleaf-$VERSION.zip"
APP_COPY="$DIST_DIR/myleaf.app"
rm -rf "$DMG" "$ZIP" "$APP_COPY"

hdiutil create -volname "myleaf $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
ditto -c -k --keepParent "$APP" "$ZIP"
cp -R "$APP" "$APP_COPY"

(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt
)

echo "==> Done"
ls -lh "$DIST_DIR"
echo
cat "$DIST_DIR/SHA256SUMS.txt"
