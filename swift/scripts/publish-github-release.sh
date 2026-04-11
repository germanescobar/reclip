#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Reclip"

if [[ $# -lt 1 ]]; then
  echo "Usage: ./scripts/publish-github-release.sh <tag> [--draft]"
  echo "Example: ./scripts/publish-github-release.sh v0.1.0 --draft"
  exit 1
fi

TAG="$1"
DRAFT_FLAG="${2:-}"

DMG_PATH="$ROOT_DIR/build/${APP_NAME}.dmg"
DMG_SHA_PATH="$ROOT_DIR/build/${APP_NAME}.dmg.sha256.txt"
ZIP_PATH="$ROOT_DIR/build/${APP_NAME}.zip"
ZIP_SHA_PATH="$ROOT_DIR/build/${APP_NAME}.zip.sha256.txt"

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is required but not installed."
    exit 1
  fi
}

require_tool gh

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: GitHub CLI is not authenticated. Run 'gh auth login' first."
  exit 1
fi

for artifact in "$DMG_PATH" "$DMG_SHA_PATH" "$ZIP_PATH" "$ZIP_SHA_PATH"; do
  if [[ ! -f "$artifact" ]]; then
    echo "Error: missing artifact: $artifact"
    echo "Run ./scripts/release.sh first."
    exit 1
  fi
done

NOTES_FILE="$ROOT_DIR/build/release-notes-${TAG}.md"
if [[ ! -f "$NOTES_FILE" ]]; then
  cat > "$NOTES_FILE" <<EOF
## ${TAG}

- First macOS desktop release artifact.
- Download \`${APP_NAME}.dmg\` for installation.
- Checksums are attached for verification.
EOF
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Release $TAG already exists. Uploading assets with --clobber."
  gh release upload "$TAG" "$DMG_PATH" "$DMG_SHA_PATH" "$ZIP_PATH" "$ZIP_SHA_PATH" --clobber
else
  echo "==> Creating GitHub release $TAG"
  if [[ "$DRAFT_FLAG" == "--draft" ]]; then
    gh release create "$TAG" "$DMG_PATH" "$DMG_SHA_PATH" "$ZIP_PATH" "$ZIP_SHA_PATH" \
      --title "$TAG" \
      --notes-file "$NOTES_FILE" \
      --draft
  else
    gh release create "$TAG" "$DMG_PATH" "$DMG_SHA_PATH" "$ZIP_PATH" "$ZIP_SHA_PATH" \
      --title "$TAG" \
      --notes-file "$NOTES_FILE"
  fi
fi

REPO_FULL_NAME="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo ""
echo "Latest download URL:"
echo "https://github.com/${REPO_FULL_NAME}/releases/latest/download/${APP_NAME}.dmg"
