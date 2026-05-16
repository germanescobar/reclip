# Desktop Release Checklist

This checklist prepares and ships a public macOS release of Reclip.

## Release Policy

Reclip intentionally ships non-notarized macOS artifacts. The project does not use Apple's notarization service, does not require notary credentials, and does not maintain a notarized release path.

Because releases are not notarized, macOS Gatekeeper may warn users when opening the app for the first time.

## 1) Prerequisites

- Xcode 16+ and command line tools installed.
- `xcodegen` installed (`brew install xcodegen`).
- Bundle ID set to `com.germanescobar.Reclip`.
- `project.yml` may remain configured for ad-hoc signing.

## 2) Release Command

From the Swift project root run the following:

```bash
./scripts/release.sh
```

## 3) Create GitHub Release

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

## 4) Release Notes

- Add release notes with:
  - version
  - fixes/features
  - non-notarized macOS build notice
  - known limitations
  - minimum macOS version (14.0+)

## 5) Smoke Test (Before Publishing)

- Download DMG on a clean macOS user account.
- Mount DMG and open the app.
- Confirm the expected non-notarized app warning behavior.
- Confirm recording start/stop and upload workflow.
