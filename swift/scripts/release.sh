#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LoomClone.xcodeproj"
SCHEME="LoomClone"
CONFIGURATION="Release"
APP_NAME="Reclip"
ARCHIVE_PATH="$ROOT_DIR/build/${APP_NAME}.xcarchive"
EXPORT_PATH="$ROOT_DIR/build/export"
APP_PATH="$EXPORT_PATH/${APP_NAME}.app"
ZIP_PATH="$ROOT_DIR/build/${APP_NAME}.zip"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/scripts/ExportOptions-DeveloperID.plist"

NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"

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
require_tool xcrun
require_tool shasum
require_tool rg

if ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "Error: 'notarytool' was not found. Install Xcode command line tools."
  exit 1
fi

echo "==> Validating inputs"
if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "Error: missing export options file at $EXPORT_OPTIONS_PLIST"
  exit 1
fi

if rg -n 'CODE_SIGN_IDENTITY:\s*"-"' "$ROOT_DIR/project.yml" >/dev/null 2>&1; then
  cat <<EOF
Error: project.yml is still configured for ad-hoc signing:
  CODE_SIGN_IDENTITY: "-"

Before running a distributable release, update project.yml to Developer ID signing.
EOF
  exit 1
fi

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat <<EOF
Error: notary profile '$NOTARY_PROFILE' is not configured.

Run this once before releasing:
  xcrun notarytool store-credentials "$NOTARY_PROFILE" \
    --apple-id "<your-apple-id>" \
    --team-id "<your-team-id>" \
    --password "<app-specific-password>"
EOF
    exit 1
  fi
fi

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
  clean archive

echo "==> Exporting signed app"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: expected app not found at $APP_PATH"
  exit 1
fi

echo "==> Creating zip for notarization and distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
  echo "==> Skipping notarization because SKIP_NOTARIZATION=1"
else
  echo "==> Submitting zip for notarization (this can take several minutes)"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "$APP_PATH"
fi

echo "==> Running Gatekeeper assessment"
spctl --assess --type execute --verbose "$APP_PATH"

echo "==> Computing SHA256 checksum"
shasum -a 256 "$ZIP_PATH" | tee "$ROOT_DIR/build/${APP_NAME}.zip.sha256.txt"

cat <<EOF

Release artifacts:
  App: $APP_PATH
  Zip: $ZIP_PATH
  SHA256: $ROOT_DIR/build/${APP_NAME}.zip.sha256.txt

Next:
  1) Upload ${APP_NAME}.zip and ${APP_NAME}.zip.sha256.txt to a GitHub release.
  2) Include release notes and macOS requirement (14.0+).
EOF
