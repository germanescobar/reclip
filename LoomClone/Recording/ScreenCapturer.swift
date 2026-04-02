import Foundation
import ScreenCaptureKit
import AVFoundation

class ScreenCapturer: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.loomclone.screen.video")
    private let audioQueue = DispatchQueue(label: "com.loomclone.screen.audio")

    var onScreenFrame: ((CMSampleBuffer) -> Void)?
    var onSystemAudio: ((CMSampleBuffer) -> Void)?

    private(set) var width: Int = 1920
    private(set) var height: Int = 1080

    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }

    func startCapture(display: SCDisplay) async throws {
        width = display.width
        height = display.height

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.showsCursor = true

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = stream

        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream.startCapture()
    }

    func stopCapture() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
        self.stream = nil
    }
}

extension ScreenCapturer: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            onScreenFrame?(sampleBuffer)
        case .audio:
            onSystemAudio?(sampleBuffer)
        @unknown default:
            break
        }
    }
}

extension ScreenCapturer: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Screen capture stopped with error: \(error.localizedDescription)")
    }
}
