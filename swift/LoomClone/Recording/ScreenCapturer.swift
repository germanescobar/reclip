import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreGraphics
import AppKit

enum RecordingCaptureTarget {
    case display(SCDisplay)
    case area(display: SCDisplay, rect: CGRect, scale: CGFloat)

    var width: Int {
        switch self {
        case .display(let display):
            return display.width
        case .area(_, let rect, let scale):
            return Self.evenDimension(Int((rect.width * scale).rounded()))
        }
    }

    var height: Int {
        switch self {
        case .display(let display):
            return display.height
        case .area(_, let rect, let scale):
            return Self.evenDimension(Int((rect.height * scale).rounded()))
        }
    }

    var displayID: CGDirectDisplayID? {
        switch self {
        case .display(let display), .area(let display, _, _):
            return display.displayID
        }
    }

    private static func evenDimension(_ value: Int) -> Int {
        max(2, value - (value % 2))
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }
}

class ScreenCapturer: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.loomclone.screen.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.loomclone.screen.audio", qos: .userInitiated)

    var onScreenFrame: ((CMSampleBuffer) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?
    private var loggedFirstFrame = false

    private(set) var width: Int = 1920
    private(set) var height: Int = 1080

    func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Attempts to actually fetch shareable content as a ground-truth permission check.
    /// `CGPreflightScreenCaptureAccess` can return stale results, especially during
    /// development when the binary is rebuilt frequently.
    func probeScreenRecordingPermission() async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return !content.displays.isEmpty
        } catch {
            return false
        }
    }

    @discardableResult
    func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }

    func getAvailableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let currentBundleID = Bundle.main.bundleIdentifier

        return content.windows
            .filter { window in
                window.isOnScreen &&
                window.windowLayer == 0 &&
                window.frame.width >= 80 &&
                window.frame.height >= 80 &&
                window.owningApplication?.bundleIdentifier != currentBundleID
            }
            .sorted { lhs, rhs in
                windowDisplayName(lhs).localizedCaseInsensitiveCompare(windowDisplayName(rhs)) == .orderedAscending
            }
    }

    func startCapture(target: RecordingCaptureTarget, captureSystemAudio: Bool = false) async throws {
        width = target.width
        height = target.height

        // Exclude this app's own windows (camera bubble, recording HUD) from
        // the capture: the camera is composited into the video separately, so
        // capturing the live bubble too would put a second, duplicated camera
        // image in the recording.
        let ownWindows = await (try? Self.ownWindows()) ?? []

        let filter: SCContentFilter
        let sourceRect: CGRect?
        switch target {
        case .display(let display):
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            sourceRect = nil
        case .area(let display, let rect, _):
            filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            sourceRect = rect
        }

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        if let sourceRect {
            config.sourceRect = sourceRect
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = captureSystemAudio
        if captureSystemAudio {
            config.sampleRate = 48000
            config.channelCount = 2
        }
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream
        loggedFirstFrame = false

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }

        try await stream.startCapture()
        avSyncLog("screen capture started (\(width)x\(height), excluding \(ownWindows.count) own windows)")
    }

    private static func ownWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let bundleID = Bundle.main.bundleIdentifier
        return content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleID }
    }

    func stopCapture() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
    }
}

func windowDisplayName(_ window: SCWindow) -> String {
    let appName = window.owningApplication?.applicationName ?? "Unknown App"
    let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if title.isEmpty {
        return appName
    }
    return "\(appName) - \(title)"
}

extension ScreenCapturer: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            if !loggedFirstFrame {
                loggedFirstFrame = true
                avSyncLog("first screen frame delivered")
            }
            onScreenFrame?(sampleBuffer)
        case .audio:
            onSystemAudio?(sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}

extension ScreenCapturer: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        avSyncLog("screen capture stopped with error: \(error)")
    }
}
