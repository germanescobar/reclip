# First Desktop Release Checklist

This checklist prepares and ships the first public macOS release of Reclip.

## 1) Prerequisites

- Active Apple Developer Program membership (paid, not only Personal Team).
- Xcode 16+ and command line tools installed.
- `xcodegen` installed (`brew install xcodegen`).
- Bundle ID set to `com.germanescobar.Reclip`.
- Team configured in `project.yml` as:
  - `DEVELOPMENT_TEAM: KH9G36PM9D`
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

## 4) Publish

- Create a git tag (example: `v0.1.0`).
- Create GitHub Release and upload:
  - `build/Reclip.zip`
  - `build/Reclip.zip.sha256.txt`
- Add release notes with:
  - version
  - fixes/features
  - known limitations
  - minimum macOS version (14.0+)

## 5) Smoke Test (Before Publishing)

- Download zip on a clean macOS user account.
- Unzip and open the app.
- Confirm no unsigned/notarization warning appears.
- Confirm recording start/stop and upload workflow.
