# First Desktop Release Checklist

This checklist prepares and ships the first public macOS release of Reclip.

## 1) Prerequisites

- Active Apple Developer Program membership (paid, not only Personal Team).
- Xcode 16+ and command line tools installed.
- `xcodegen` installed (`brew install xcodegen`).
- Bundle ID set to `com.germanescobar.Reclip`.
- Team selected locally in Xcode for your own Apple Developer account.
- `project.yml` signing updated for distribution (not ad-hoc `"-"` identity).

## 2) One-time Notary Credential Setup

Run once on your machine:

```bash
xcrun notarytool store-credentials "AC_NOTARY" \
  --apple-id "<your-apple-id>" \
  --team-id "<your-team-id>" \
  --password "<app-specific-password>"
```

## 3) Release Command

From the Swift project root:

```bash
cd /Users/germanescobar/Projects/incubating/recording/swift
./scripts/release.sh
```

If you need to test archive/export without notarization:

```bash
SKIP_NOTARIZATION=1 ./scripts/release.sh
```

## 4) Create GitHub Release

- Create and upload release assets:

```bash
./scripts/publish-github-release.sh v0.1.0 --draft
```

This uploads:
- `build/Reclip.dmg`
- `build/Reclip.dmg.sha256.txt`
- `build/Reclip.zip`
- `build/Reclip.zip.sha256.txt`

The latest stable download URL is:
- `https://github.com/germanescobar/reclip/releases/latest/download/Reclip.dmg`

## 5) Release Notes

- Add release notes with:
  - version
  - fixes/features
  - known limitations
  - minimum macOS version (14.0+)

## 6) Smoke Test (Before Publishing)

- Download DMG on a clean macOS user account.
- Mount DMG and open the app.
- Confirm no unsigned/notarization warning appears.
- Confirm recording start/stop and upload workflow.
