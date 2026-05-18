#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LoomClone.xcodeproj"
SCHEME="LoomClone"
CONFIGURATION="Release"
APP_NAME="Reclip"
ARCHIVE_PATH="$ROOT_DIR/build/${APP_NAME}.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
ZIP_PATH="$ROOT_DIR/build/${APP_NAME}.zip"
DMG_PATH="$ROOT_DIR/build/${APP_NAME}.dmg"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is required but not installed."
    exit 1
  fi
}

echo "==> Validating tools"
require_tool xcodegen
require_tool xcodebuild
require_tool ditto
require_tool shasum
require_tool hdiutil

echo "==> Validating inputs"
echo "This project intentionally ships non-notarized ad-hoc macOS builds."

echo "==> Cleaning previous build artifacts"
rm -rf "$ROOT_DIR/build"
mkdir -p "$ROOT_DIR/build"

echo "==> Generating Xcode project"
cd "$ROOT_DIR"
xcodegen generate

echo "==> Archiving ${APP_NAME}.app"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_IDENTITY="-" \
  clean archive

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: expected app not found at $APP_PATH"
  exit 1
fi

echo "==> Creating zip for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Creating DMG for distribution"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "==> Computing SHA256 checksums"
shasum -a 256 "$ZIP_PATH" | tee "$ROOT_DIR/build/${APP_NAME}.zip.sha256.txt"
shasum -a 256 "$DMG_PATH" | tee "$ROOT_DIR/build/${APP_NAME}.dmg.sha256.txt"

cat <<EOF

Release artifacts:
  App: $APP_PATH
  Zip: $ZIP_PATH
  Dmg: $DMG_PATH
  SHA256 (zip): $ROOT_DIR/build/${APP_NAME}.zip.sha256.txt
  SHA256 (dmg): $ROOT_DIR/build/${APP_NAME}.dmg.sha256.txt

Next:
  1) Upload ${APP_NAME}.dmg, ${APP_NAME}.zip, and checksum files to a GitHub release.
  2) Include release notes, macOS requirement (14.0+), and a non-notarized build notice.
EOF
