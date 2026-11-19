#!/usr/bin/env bash
#
# Builds a universal, ad-hoc signed release of myleaf and packages it as a
# DMG, a ZIP, a .pkg installer, and an uninstaller .pkg under dist/.
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
PKGROOT="$(mktemp -d "${TMPDIR:-/tmp}/myleaf-pkgroot.XXXXXX")"
APP="$BUILD_DIR/Build/Products/Release/myleaf.app"

cleanup() { rm -rf "$BUILD_DIR" "$STAGE" "$PKGROOT"; }
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

echo "==> Building installer packages"
DMG="$DIST_DIR/myleaf-$VERSION.dmg"
ZIP="$DIST_DIR/myleaf-$VERSION.zip"
PKG="$DIST_DIR/myleaf-$VERSION.pkg"
UNINSTALLER_PKG="$DIST_DIR/myleaf-uninstaller-$VERSION.pkg"
KEEP_UNINSTALLER_PKG="$DIST_DIR/myleaf-uninstaller-keepdata-$VERSION.pkg"

rm -rf "$DMG" "$ZIP" "$PKG" "$UNINSTALLER_PKG" "$KEEP_UNINSTALLER_PKG" "$DIST_DIR/myleaf.app"
# Drop artifacts from older versions so dist/ only contains the current build.
find "$DIST_DIR" -maxdepth 1 -type f \
    \( -name 'myleaf-*.dmg' -o -name 'myleaf-*.zip' -o -name 'myleaf-*.pkg' \) \
    ! -name "myleaf-$VERSION.dmg" \
    ! -name "myleaf-$VERSION.zip" \
    ! -name "myleaf-$VERSION.pkg" \
    ! -name "myleaf-uninstaller-$VERSION.pkg" \
    ! -name "myleaf-uninstaller-keepdata-$VERSION.pkg" -delete

chmod +x \
    "$ROOT/scripts/pkg/install/preinstall" \
    "$ROOT/scripts/pkg/uninstall/preinstall" \
    "$ROOT/scripts/pkg/uninstall-keepdata/preinstall"

# Installer: payload root /Applications/myleaf.app, with a preinstall script
# that quits a running copy.
mkdir -p "$PKGROOT/Applications"
cp -R "$APP" "$PKGROOT/Applications/myleaf.app"
pkgbuild \
    --root "$PKGROOT" \
    --install-location / \
    --identifier com.65zlui.myleaf \
    --version "$VERSION" \
    --min-os-version 14.0 \
    --ownership recommended \
    --scripts "$ROOT/scripts/pkg/install" \
    "$PKG"

pkgutil --payload-files "$PKG" | grep -q "Applications/myleaf.app" \
    || { echo "error: installer package is missing myleaf.app" >&2; exit 1; }

# Uninstaller: no payload; the preinstall script removes the app and data.
pkgbuild \
    --nopayload \
    --identifier com.65zlui.myleaf.uninstaller \
    --version "$VERSION" \
    --scripts "$ROOT/scripts/pkg/uninstall" \
    "$UNINSTALLER_PKG"

# Keep-data uninstaller: removes only /Applications/myleaf.app.
pkgbuild \
    --nopayload \
    --identifier com.65zlui.myleaf.uninstaller.keepdata \
    --version "$VERSION" \
    --scripts "$ROOT/scripts/pkg/uninstall-keepdata" \
    "$KEEP_UNINSTALLER_PKG"

echo "==> Packaging DMG and ZIP"
cp -R "$APP" "$STAGE/myleaf.app"
ln -s /Applications "$STAGE/Applications"
cp "$UNINSTALLER_PKG" "$STAGE/Uninstall myleaf.pkg"
cp "$KEEP_UNINSTALLER_PKG" "$STAGE/Uninstall myleaf (keep data).pkg"

hdiutil create -volname "myleaf $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
ditto -c -k --keepParent "$APP" "$ZIP"

(
    cd "$DIST_DIR"
    shasum -a 256 \
        "$(basename "$DMG")" \
        "$(basename "$ZIP")" \
        "$(basename "$PKG")" \
        "$(basename "$UNINSTALLER_PKG")" \
        "$(basename "$KEEP_UNINSTALLER_PKG")" > SHA256SUMS.txt
)

echo "==> Done"
ls -lh "$DIST_DIR"
echo
cat "$DIST_DIR/SHA256SUMS.txt"
