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
DMG_PATH="$ROOT_DIR/build/${APP_NAME}.dmg"
EXPORT_OPTIONS_PLIST="$ROOT_DIR/scripts/ExportOptions-DeveloperID.plist"
LOCAL_RELEASE_CONFIG="$ROOT_DIR/.release.local"

# Load local ignored release config (if present), then allow env vars to override.
if [[ -f "$LOCAL_RELEASE_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$LOCAL_RELEASE_CONFIG"
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"

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
require_tool hdiutil

if ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "Error: 'notarytool' was not found. Install Xcode command line tools."
  exit 1
fi

echo "==> Validating inputs"
if [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
  echo "Error: missing export options file at $EXPORT_OPTIONS_PLIST"
  exit 1
fi

if grep -Eq 'CODE_SIGN_IDENTITY:[[:space:]]*"-"' "$ROOT_DIR/project.yml"; then
  if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
    echo "Warning: using ad-hoc signing because SKIP_NOTARIZATION=1."
  else
    cat <<EOF
Error: project.yml is still configured for ad-hoc signing:
  CODE_SIGN_IDENTITY: "-"

Before running a distributable release, update project.yml to Developer ID signing.
EOF
    exit 1
  fi
fi

if [[ "${SKIP_NOTARIZATION}" != "1" ]]; then
  if [[ -z "${DEVELOPMENT_TEAM}" ]] && ! grep -Eq 'DEVELOPMENT_TEAM:[[:space:]]*[A-Z0-9]{10}' "$ROOT_DIR/project.yml"; then
    cat <<EOF
Error: no team configured for export.

Set a team id when running the script:
  DEVELOPMENT_TEAM="<YOUR_TEAM_ID>" ./scripts/release.sh
EOF
    exit 1
  fi

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
if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
    CODE_SIGN_STYLE=Automatic \
    clean archive
else
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    clean archive
fi

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
  APP_PATH="$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app"
  echo "==> Skipping exportArchive because SKIP_NOTARIZATION=1"
else
  echo "==> Exporting signed app"
  if [[ -n "${DEVELOPMENT_TEAM}" ]]; then
    xcodebuild \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
      -exportPath "$EXPORT_PATH" \
      DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  else
    xcodebuild \
      -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
      -exportPath "$EXPORT_PATH"
  fi
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: expected app not found at $APP_PATH"
  exit 1
fi

echo "==> Creating zip for notarization and distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Creating DMG for distribution"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
  echo "==> Skipping notarization because SKIP_NOTARIZATION=1"
else
  echo "==> Submitting DMG for notarization (this can take several minutes)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

  echo "==> Stapling notarization ticket to DMG"
  xcrun stapler staple "$DMG_PATH"
fi

echo "==> Running Gatekeeper assessment"
if [[ "${SKIP_NOTARIZATION}" == "1" ]]; then
  if ! spctl --assess --type execute --verbose "$APP_PATH"; then
    echo "Warning: Gatekeeper rejected app (expected in SKIP_NOTARIZATION=1 test mode)."
  fi
  if ! spctl --assess --type open --verbose "$DMG_PATH"; then
    echo "Warning: Gatekeeper rejected DMG (expected in SKIP_NOTARIZATION=1 test mode)."
  fi
else
  spctl --assess --type execute --verbose "$APP_PATH"
  spctl --assess --type open --verbose "$DMG_PATH"
fi

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
  1) Upload ${APP_NAME}.dmg and ${APP_NAME}.dmg.sha256.txt to a GitHub release.
  2) Include release notes and macOS requirement (14.0+).
EOF
