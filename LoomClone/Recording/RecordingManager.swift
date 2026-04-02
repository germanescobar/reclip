import Foundation
import AppKit
import AVFoundation
import ScreenCaptureKit
import Observation

enum RecordingState: Equatable {
    case idle
    case preparing
    case recording
    case stopping
    case saved(URL)
    case uploading
    case uploaded(String)
    case error(String)

    var displayText: String {
        switch self {
        case .idle: return "Ready to record"
        case .preparing: return "Preparing..."
        case .recording: return "Recording"
        case .stopping: return "Stopping..."
        case .saved: return "Recording saved"
        case .uploading: return "Uploading..."
        case .uploaded(let url): return "Uploaded: \(url)"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.recording, .recording),
             (.stopping, .stopping), (.uploading, .uploading):
            return true
        case (.saved(let a), .saved(let b)):
            return a == b
        case (.uploaded(let a), .uploaded(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

@Observable
class RecordingManager: @unchecked Sendable {
    private enum BufferedSampleKind {
        case screen
        case systemAudio
        case micAudio
    }

    var state: RecordingState = .idle {
        didSet {
            onRecordingChanged?(isRecording)
        }
    }
    var uploadProgress: Double = 0
    var recordingDuration: TimeInterval = 0
    var availableDisplays: [SCDisplay] = []
    var cameraOverlayPosition = CGPoint(x: 0.85, y: 0.2)
    var selectedDisplayID: CGDirectDisplayID?
    @ObservationIgnored var onRecordingChanged: ((Bool) -> Void)?
    @ObservationIgnored var onDisplaysLoaded: (() -> Void)?

    let screenCapturer = ScreenCapturer()
    let cameraCapturer = CameraCapturer()
    private let compositor = VideoCompositor()
    private let uploader = S3Uploader()
    @ObservationIgnored private let floatingCameraWindowController = FloatingCameraWindowController()

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?

    private var sessionStarted = false
    private var sessionStartTime: CMTime?
    private var startTime: Date?
    private var durationTimer: Timer?
    private var pendingScreenSamples: [CMSampleBuffer] = []
    private var pendingSystemAudioSamples: [CMSampleBuffer] = []
    private var pendingMicAudioSamples: [CMSampleBuffer] = []

    private let writerQueue = DispatchQueue(label: "com.loomclone.writer")

    var isRecording: Bool {
        state == .recording
    }

    var selectedDisplay: SCDisplay? {
        guard let selectedDisplayID else { return availableDisplays.first }
        return availableDisplays.first { $0.displayID == selectedDisplayID } ?? availableDisplays.first
    }

    func loadDisplays() async {
        do {
            availableDisplays = try await screenCapturer.getAvailableDisplays()
            if selectedDisplayID == nil {
                selectedDisplayID = availableDisplays.first?.displayID
            }
            onDisplaysLoaded?()
        } catch {
            state = .error("Failed to load displays: \(error.localizedDescription)")
        }
    }

    func showCameraPreview(for display: SCDisplay? = nil) async {
        guard !isRecording else { return }

        let granted = await cameraCapturer.requestPermissions()
        guard granted else {
            state = .error("Camera/microphone permissions denied")
            return
        }

        do {
            try cameraCapturer.setupSession()
            cameraCapturer.startCapture()

            if let screen = Self.screen(for: display?.displayID) ?? Self.preferredScreen() {
                await MainActor.run {
                    floatingCameraWindowController.onNormalizedCenterChanged = { [weak self] normalizedCenter in
                        self?.updateCameraOverlayPosition(normalizedCenter)
                    }
                    floatingCameraWindowController.show(
                        captureSession: cameraCapturer.session,
                        on: screen,
                        normalizedCenter: cameraOverlayPosition
                    )
                }
            }
        } catch {
            state = .error("Failed to show camera preview: \(error.localizedDescription)")
        }
    }

    func hideCameraPreview() {
        guard !isRecording else { return }
        cameraCapturer.stopCapture()
        Task { @MainActor in
            floatingCameraWindowController.hide()
        }
    }

    func startRecording(display: SCDisplay) async {
        state = .preparing
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0
        resetWriterState()
        compositor.reset()
        compositor.overlayNormalizedCenter = cameraOverlayPosition

        do {
            guard let screen = Self.screen(for: display.displayID) else {
                await MainActor.run {
                    floatingCameraWindowController.hide()
                }
                state = .error("Could not find the selected display")
                return
            }

            let granted = await cameraCapturer.requestPermissions()
            guard granted else {
                await MainActor.run {
                    floatingCameraWindowController.hide()
                }
                state = .error("Camera/microphone permissions denied")
                return
            }

            try cameraCapturer.setupSession()

            // Setup output file
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("loomclone-\(UUID().uuidString).mp4")

            // Setup AVAssetWriter
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: display.width,
                AVVideoHeightKey: display.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 6_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            ]
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput.expectsMediaDataInRealTime = true

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            systemAudioInput.expectsMediaDataInRealTime = true

            let micAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            micAudioInput.expectsMediaDataInRealTime = true

            writer.add(videoInput)
            writer.add(systemAudioInput)
            writer.add(micAudioInput)

            self.assetWriter = writer
            self.videoInput = videoInput
            self.systemAudioInput = systemAudioInput
            self.micAudioInput = micAudioInput

            // Wire up callbacks
            screenCapturer.onScreenFrame = { [weak self] sampleBuffer in
                self?.handleScreenFrame(sampleBuffer)
            }
            screenCapturer.onSystemAudio = { [weak self] sampleBuffer in
                self?.handleSystemAudio(sampleBuffer)
            }
            cameraCapturer.onCameraFrame = { [weak self] sampleBuffer in
                self?.compositor.updateCameraFrame(sampleBuffer)
            }
            cameraCapturer.onMicAudio = { [weak self] sampleBuffer in
                self?.handleMicAudio(sampleBuffer)
            }

            // Start capturing
            try await screenCapturer.startCapture(display: display)
            cameraCapturer.startCapture()

            await MainActor.run {
                floatingCameraWindowController.onNormalizedCenterChanged = { [weak self] normalizedCenter in
                    self?.updateCameraOverlayPosition(normalizedCenter)
                }
                floatingCameraWindowController.show(
                    captureSession: cameraCapturer.session,
                    on: screen,
                    normalizedCenter: cameraOverlayPosition
                )
            }

            // Start duration timer
            startTime = Date()
            let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, let startTime = self.startTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
            RunLoop.main.add(timer, forMode: .common)
            durationTimer = timer

            state = .recording
        } catch {
            await MainActor.run {
                floatingCameraWindowController.hide()
            }
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() async {
        guard state == .recording else { return }
        state = .stopping

        durationTimer?.invalidate()
        durationTimer = nil
        await MainActor.run {
            floatingCameraWindowController.hide()
        }

        // Stop capture sources
        cameraCapturer.stopCapture()
        try? await screenCapturer.stopCapture()

        // Finalize the asset writer
        guard let writer = assetWriter else {
            state = .error("No active writer")
            return
        }

        let outputURL = writer.outputURL

        await withCheckedContinuation { continuation in
            writerQueue.async {
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.micAudioInput?.markAsFinished()

                writer.finishWriting {
                    if writer.status == .completed {
                        DispatchQueue.main.async {
                            self.state = .saved(outputURL)
                        }
                    } else {
                        DispatchQueue.main.async {
                            self.state = .error("Failed to save: \(writer.error?.localizedDescription ?? "unknown")")
                        }
                    }
                    continuation.resume()
                }
            }
        }

        // Cleanup
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        micAudioInput = nil
        resetWriterState()
        compositor.reset()
    }

    func uploadRecording(fileURL: URL) async {
        state = .uploading
        uploadProgress = 0

        do {
            let url = try await uploader.upload(fileURL: fileURL) { [weak self] progress in
                DispatchQueue.main.async {
                    self?.uploadProgress = progress
                }
            }
            state = .uploaded(url)
        } catch {
            state = .error("Upload failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
        recordingDuration = 0
        uploadProgress = 0
        resetWriterState()
        compositor.reset()
        hideCameraPreview()
    }

    // MARK: - Sample buffer handlers

    private func handleScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self,
                  let writer = self.assetWriter,
                  let input = self.videoInput else { return }

            guard writer.status != .failed, writer.status != .cancelled else { return }

            if !self.sessionStarted {
                self.pendingScreenSamples.append(sampleBuffer)
                self.tryStartSessionIfReady(writer: writer)
                return
            }

            self.appendScreenSample(sampleBuffer, writer: writer, input: input)
        }
    }

    private func handleSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self,
                  let writer = self.assetWriter,
                  let input = self.systemAudioInput else { return }

            guard writer.status != .failed, writer.status != .cancelled else { return }

            if !self.sessionStarted {
                self.pendingSystemAudioSamples.append(sampleBuffer)
                self.tryStartSessionIfReady(writer: writer)
                return
            }

            self.appendAudioSample(sampleBuffer, writer: writer, input: input)
        }
    }

    private func handleMicAudio(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self,
                  let writer = self.assetWriter,
                  let input = self.micAudioInput else { return }

            guard writer.status != .failed, writer.status != .cancelled else { return }

            if !self.sessionStarted {
                self.pendingMicAudioSamples.append(sampleBuffer)
                self.tryStartSessionIfReady(writer: writer)
                return
            }

            self.appendAudioSample(sampleBuffer, writer: writer, input: input)
        }
    }

    private func tryStartSessionIfReady(writer: AVAssetWriter) {
        guard !sessionStarted else { return }
        guard let firstScreen = pendingScreenSamples.first,
              let firstSystemAudio = pendingSystemAudioSamples.first,
              let firstMicAudio = pendingMicAudioSamples.first else {
            return
        }

        let startTime = [
            CMSampleBufferGetPresentationTimeStamp(firstScreen),
            CMSampleBufferGetPresentationTimeStamp(firstSystemAudio),
            CMSampleBufferGetPresentationTimeStamp(firstMicAudio)
        ].min()!

        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: startTime)
        sessionStarted = true
        sessionStartTime = startTime

        flushPendingSamples(writer: writer)
    }

    private func flushPendingSamples(writer: AVAssetWriter) {
        guard sessionStarted else { return }

        let bufferedSamples =
            pendingScreenSamples.map { (kind: BufferedSampleKind.screen, sample: $0) } +
            pendingSystemAudioSamples.map { (kind: BufferedSampleKind.systemAudio, sample: $0) } +
            pendingMicAudioSamples.map { (kind: BufferedSampleKind.micAudio, sample: $0) }

        pendingScreenSamples.removeAll()
        pendingSystemAudioSamples.removeAll()
        pendingMicAudioSamples.removeAll()

        for buffered in bufferedSamples.sorted(by: {
            CMSampleBufferGetPresentationTimeStamp($0.sample) < CMSampleBufferGetPresentationTimeStamp($1.sample)
        }) {
            switch buffered.kind {
            case .screen:
                guard let input = videoInput else { continue }
                appendScreenSample(buffered.sample, writer: writer, input: input)
            case .systemAudio:
                guard let input = systemAudioInput else { continue }
                appendAudioSample(buffered.sample, writer: writer, input: input)
            case .micAudio:
                guard let input = micAudioInput else { continue }
                appendAudioSample(buffered.sample, writer: writer, input: input)
            }
        }
    }

    private func appendScreenSample(_ sampleBuffer: CMSampleBuffer, writer: AVAssetWriter, input: AVAssetWriterInput) {
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }

        if let composited = compositor.compositeFrame(
            sampleBuffer,
            width: screenCapturer.width,
            height: screenCapturer.height
        ) {
            input.append(composited)
        }
    }

    private func appendAudioSample(_ sampleBuffer: CMSampleBuffer, writer: AVAssetWriter, input: AVAssetWriterInput) {
        guard writer.status == .writing, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    private func resetWriterState() {
        sessionStarted = false
        sessionStartTime = nil
        pendingScreenSamples.removeAll()
        pendingSystemAudioSamples.removeAll()
        pendingMicAudioSamples.removeAll()
    }

    private func updateCameraOverlayPosition(_ normalizedCenter: CGPoint) {
        let clampedCenter = CGPoint(
            x: min(max(normalizedCenter.x, 0), 1),
            y: min(max(normalizedCenter.y, 0), 1)
        )
        cameraOverlayPosition = clampedCenter
        compositor.overlayNormalizedCenter = clampedCenter
    }

    private static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }

        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == displayID
        }
    }

    private static func preferredScreen() -> NSScreen? {
        if let mainScreen = NSScreen.main {
            return mainScreen
        }

        if let firstDisplay = NSScreen.screens.first {
            return firstDisplay
        }

        return nil
    }
}
