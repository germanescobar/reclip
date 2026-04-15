# Recording

A Loom-like screen recording application with a native macOS client and a Next.js web app.

## Getting Started

1. Sign up at [reclip.click](https://reclip.click)
2. Download the latest release from the [Releases](https://github.com/germanescobar/reclip/releases) page
3. Open the app and sign in with your account

## Project Structure

```
├── swift/          # Native macOS screen recorder (Swift/SwiftUI)
└── web/            # Web dashboard and sharing (Next.js + Supabase)
```

### macOS App (`swift/`)

A native macOS screen recording app built with Swift that captures screen, system audio, and camera with a picture-in-picture overlay. Recordings are uploaded to AWS S3.

**Tech stack:** Swift 5.9, SwiftUI, ScreenCaptureKit, AVFoundation, Core Image, Metal, AWS SDK for Swift

**Requirements:** macOS 14.0+ (Sonoma), Xcode 15+

See [`swift/README.md`](swift/README.md) for setup and usage instructions.

### Web App (`web/`)

A Next.js web application that serves as the dashboard for managing and sharing recordings. Includes authentication, a recording viewer, and shareable links.

**Tech stack:** Next.js 16, React 19, Supabase (auth + database), Tailwind CSS, shadcn/ui

**Key features:**
- User authentication (email/password, device login)
- Dashboard for managing recordings
- Shareable recording links (`/r/[shortId]`)
- API key management

#### Getting Started

```bash
cd web
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to view the app.

## License

MIT
