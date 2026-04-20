# LoomClone - macOS Screen Recorder PoC

A native macOS screen recording application that captures screen, system audio, and camera with picture-in-picture overlay, then uploads to AWS S3.

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15+
- Swift 5.9+
- AWS credentials for S3 upload (optional)

## Setup

### 1. Generate Xcode Project Files

```bash
brew install xcodegen
./scripts/regenerate_xcodeproj.sh
```

This creates `LoomClone.xcodeproj` from [`project.yml`](/Users/germanescobar/Projects/incubating/recording/swift/project.yml).

`project.yml` is the source of truth for the macOS Xcode project. When you add, remove, or move Swift files, regenerate the project instead of hand-editing `LoomClone.xcodeproj/project.pbxproj`.

### 2. Open in Xcode

```bash
open LoomClone.xcodeproj
```

### 3. Configure AWS (optional)

Click "Settings" in the app and configure:
- Access Key ID
- Secret Access Key  
- Region
- Bucket name

Or set environment variables:
```bash
export AWS_ACCESS_KEY_ID=your_key
export AWS_SECRET_ACCESS_KEY=your_secret
export AWS_REGION=us-east-1
export S3_BUCKET=your_bucket
```

## Building

Build in Xcode or via command line:

```bash
xcodebuild -project LoomClone.xcodeproj -scheme LoomClone -configuration Debug build
```

If you change the Swift file layout, run `./scripts/regenerate_xcodeproj.sh` before building in Xcode.

## Releases

For first-time release setup and notarization, see `docs/FIRST_RELEASE_CHECKLIST.md`.

Once prerequisites are complete, run:

```bash
./scripts/release.sh
```

## Usage

1. Grant camera/microphone permissions when prompted
2. Select a display to record
3. Click the red record button
4. Drag the floating camera bubble to reposition
5. Click again to stop recording
6. Choose upload to S3, open file, or open folder

## Architecture

- **ScreenCaptureKit**: Screen capture with system audio
- **AVFoundation**: Camera and microphone capture
- **Core Image + Metal**: Real-time camera overlay compositing
- **AVAssetWriter**: H.264 video + AAC audio encoding
- **AWS SDK for Swift**: S3 upload with progress tracking

## Project Structure

```
recording/
├── project.yml                    # Xcodegen configuration
├── LoomClone.xcodeproj/          # Generated Xcode project
├── LoomClone/
│   ├── ContentView.swift         # Main UI
│   ├── Recording/
│   │   ├── RecordingManager.swift
│   │   ├── ScreenCapturer.swift
│   │   └── CameraCapturer.swift
│   └── Upload/
│       └── S3Uploader.swift
└── PLAN.md                       # Implementation plan
```

## License

MIT
