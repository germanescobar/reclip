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

enum MicrophoneCheckState: Equatable {
    case idle
    case checking
    case ready
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Run a quick mic check before recording."
        case .checking:
            return "Listening... say a few words."
        case .ready:
            return "Microphone signal detected."
        case .failed(let message):
            return message
        }
    }
}

enum RecordingAudioStatus: Equatable {
    case idle
    case waiting(String)
    case live(String)
    case validated(String)
    case failed(String)

    var displayText: String {
        switch self {
        case .idle:
            return "Recording audio feedback will appear here."
        case .waiting(let message),
             .live(let message),
             .validated(let message),
             .failed(let message):
            return message
        }
    }
}

@Observable
class RecordingManager: @unchecked Sendable {
    private enum BufferedSampleKind {
        case screen
        case audio
    }

    var state: RecordingState = .idle {
        didSet {
            onStateChanged?(state)
            onRecordingChanged?(isRecording)
            onRecordingMetricsChanged?()
        }
    }
    var uploadProgress: Double = 0
    var recordingDuration: TimeInterval = 0 {
        didSet {
            onRecordingMetricsChanged?()
        }
    }
    var availableDisplays: [SCDisplay] = []
    var availableCameras: [AVCaptureDevice] = []
    var availableMicrophones: [AVCaptureDevice] = []
    var cameraPermissionGranted = false
    var microphonePermissionGranted = false
    var screenPermissionGranted = false
    var needsAppRestart = false
    var cameraOverlayPosition = CGPoint(x: 0.85, y: 0.2)
    var microphoneCheckState: MicrophoneCheckState = .idle
    var microphoneLevel: Double = 0
    var recordingAudioStatus: RecordingAudioStatus = .idle {
        didSet {
            onRecordingMetricsChanged?()
        }
    }
    var recordingAudioLevel: Double = 0
    var selectedDisplayID: CGDirectDisplayID?
    var selectedCameraID: String? {
        didSet {
            refreshPreviewCaptureDevicesIfNeeded()
        }
    }
    var selectedMicrophoneID: String? {
        didSet {
            invalidateMicrophoneCheck()
            refreshPreviewCaptureDevicesIfNeeded()
        }
    }
    @ObservationIgnored var onRecordingChanged: ((Bool) -> Void)?
    @ObservationIgnored var onStateChanged: ((RecordingState) -> Void)?
    @ObservationIgnored var onDisplaysLoaded: (() -> Void)?
    @ObservationIgnored var onRecordingMetricsChanged: (() -> Void)?

    let screenCapturer = ScreenCapturer()
    let cameraCapturer = CameraCapturer()
    private let compositor = VideoCompositor()
    private let uploader = S3Uploader()
    private let apiClient = RecordingAPIClient()
    @ObservationIgnored private let floatingCameraWindowController = FloatingCameraWindowController()

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?

    private var sessionStarted = false
    private var sessionStartTime: CMTime?
    private var startTime: Date?
    private var durationTimer: Timer?
    private var pendingScreenSamples: [CMSampleBuffer] = []
    private var pendingAudioSamples: [CMSampleBuffer] = []
    private var firstScreenPTS: CMTime?
    private var firstAudioPTS: CMTime?
    private var lastVerifiedMicrophoneSignalAt: Date?
    private var hasWrittenAudioSamples = false
    private var isRunningMicrophoneCheck = false
    @ObservationIgnored private var previewRefreshTask: Task<Void, Never>?

    private let writerQueue = DispatchQueue(label: "com.loomclone.writer")

    init() {
        configureCaptureCallbacks()
    }

    var isRecording: Bool {
        state == .recording
    }

    var permissionsReady: Bool {
        cameraPermissionGranted && microphonePermissionGranted && screenPermissionGranted && !needsAppRestart
    }

    var canRequestScreenPermission: Bool {
        cameraPermissionGranted && microphonePermissionGranted
    }

    var selectedDisplay: SCDisplay? {
        guard let selectedDisplayID else { return availableDisplays.first }
        return availableDisplays.first { $0.displayID == selectedDisplayID } ?? availableDisplays.first
    }

    var selectedCamera: AVCaptureDevice? {
        guard let selectedCameraID else { return availableCameras.first }
        return availableCameras.first { $0.uniqueID == selectedCameraID } ?? availableCameras.first
    }

    var selectedMicrophone: AVCaptureDevice? {
        guard let selectedMicrophoneID else { return availableMicrophones.first }
        return availableMicrophones.first { $0.uniqueID == selectedMicrophoneID } ?? availableMicrophones.first
    }

    var selectedMicrophoneName: String {
        selectedMicrophone?.localizedName ?? "the selected microphone"
    }

    func prepare() async {
        await refreshPermissionStatusAsync()
        loadDevices()

        if permissionsReady {
            await loadDisplays()
            syncSelections()
        } else {
            availableDisplays = []
        }
    }

    func refreshPermissionStatus() {
        cameraPermissionGranted = cameraCapturer.hasCameraPermission()
        microphonePermissionGranted = cameraCapturer.hasMicrophonePermission()
        screenPermissionGranted = screenCapturer.hasScreenRecordingPermission()
        if !screenPermissionGranted {
            needsAppRestart = false
        }
    }

    /// Re-checks screen recording permission using a real ScreenCaptureKit probe
    /// instead of the potentially stale `CGPreflightScreenCaptureAccess`.
    func refreshPermissionStatusAsync() async {
        cameraPermissionGranted = cameraCapturer.hasCameraPermission()
        microphonePermissionGranted = cameraCapturer.hasMicrophonePermission()

        let probeResult = await screenCapturer.probeScreenRecordingPermission()
        screenPermissionGranted = probeResult

        if probeResult {
            needsAppRestart = false
        }
    }

    func requestCameraAndMicrophonePermissions() async {
        _ = await cameraCapturer.requestCameraPermission()
        _ = await cameraCapturer.requestMicrophonePermission()
        refreshPermissionStatus()
        loadDevices()
    }

    func beginScreenRecordingPermissionFlow() async {
        let screenWasGranted = screenPermissionGranted
        let didGrantImmediately = screenCapturer.requestScreenRecordingPermission()
        // Use the real probe to check if macOS has already applied the permission,
        // avoiding an unnecessary restart when the binary hasn't changed.
        await refreshPermissionStatusAsync()

        if screenPermissionGranted {
            needsAppRestart = false
        } else if !screenWasGranted && didGrantImmediately {
            // CGRequestScreenCaptureAccess returned true but the probe failed —
            // macOS likely needs an app restart to activate the permission.
            needsAppRestart = true
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        needsAppRestart = true
        NSWorkspace.shared.open(url)
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }

    func loadDisplays() async {
        guard screenPermissionGranted else {
            availableDisplays = []
            return
        }

        do {
            availableDisplays = try await screenCapturer.getAvailableDisplays()
            syncSelections()
            onDisplaysLoaded?()
        } catch {
            state = .error("Failed to load displays: \(error.localizedDescription)")
        }
    }

    func loadDevices() {
        availableCameras = CameraCapturer.availableCameras()
        availableMicrophones = CameraCapturer.availableMicrophones()
        if selectedCameraID == nil {
            selectedCameraID = availableCameras.first?.uniqueID
        }
        if selectedMicrophoneID == nil {
            selectedMicrophoneID = availableMicrophones.first?.uniqueID
        }
    }

    func showCameraPreview(for display: SCDisplay? = nil) async {
        guard !isRecording else { return }
        guard permissionsReady else { return }

        let granted = await cameraCapturer.requestPermissions()
        guard granted else {
            state = .error("Camera/microphone permissions denied")
            return
        }

        do {
            try restartCameraSession(
                camera: selectedCamera,
                microphone: selectedMicrophone,
                includeCamera: true,
                includeMicrophone: true
            )

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
        previewRefreshTask?.cancel()
        previewRefreshTask = nil
        cameraCapturer.stopCapture(waitUntilStopped: true)
        Task { @MainActor in
            floatingCameraWindowController.hide()
        }
    }

    func startRecording(display: SCDisplay) async {
        guard permissionsReady else {
            state = .error("Finish granting permissions before recording")
            return
        }

        state = .preparing
        durationTimer?.invalidate()
        durationTimer = nil
        recordingDuration = 0
        resetWriterState()
        resetRecordingAudioFeedback()
        compositor.reset()
        compositor.overlayNormalizedCenter = cameraOverlayPosition

        do {
            let microphoneReady = await runMicrophoneCheckIfNeeded()
            guard microphoneReady else {
                state = .error("No microphone signal detected. Run the mic check, verify the selected input, and try again.")
                return
            }

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

            try restartCameraSession(
                camera: selectedCamera,
                microphone: selectedMicrophone,
                includeCamera: true,
                includeMicrophone: true
            )

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
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput.expectsMediaDataInRealTime = true

            writer.add(videoInput)
            writer.add(audioInput)

            self.assetWriter = writer
            self.videoInput = videoInput
            self.audioInput = audioInput

            // Start screen capture
            try await screenCapturer.startCapture(display: display, captureSystemAudio: false)

            // Start the camera session synchronously so startRunning()
            // completes before the preview layer connects to it.
            cameraCapturer.startCapture(waitUntilRunning: true)

            await MainActor.run {
                recordingAudioStatus = .waiting("Waiting for microphone audio from \(selectedMicrophoneName)...")
            }

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
                self.audioInput?.markAsFinished()

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
        await validateSavedRecordingAudio(at: outputURL)
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        resetWriterState()
        compositor.reset()
    }

    func uploadRecording(fileURL: URL, title: String? = nil, description: String? = nil) async {
        state = .uploading
        uploadProgress = 0

        do {
            let s3URL = try await uploader.upload(fileURL: fileURL) { [weak self] progress in
                DispatchQueue.main.async {
                    self?.uploadProgress = progress
                }
            }

            print("[Upload] S3 upload complete. URL: \(s3URL)")

            // Create recording via API to get a shareable URL
            let recordingTitle = title ?? fileURL.deletingPathExtension().lastPathComponent
            let settings = AWSSettingsStorage.load()
            print("[Upload] API Base URL: '\(settings.apiBaseURL)', API Key present: \(!settings.apiKey.isEmpty)")

            do {
                let shareableURL = try await apiClient.createRecording(title: recordingTitle, s3URL: s3URL, description: description)
                print("[Upload] API success. Shareable URL: \(shareableURL)")
                state = .uploaded(shareableURL)
            } catch {
                print("[Upload] API call failed: \(error)")
                // Fall back to S3 URL but show warning
                state = .uploaded(s3URL)
            }
        } catch {
            state = .error("Upload failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
        recordingDuration = 0
        uploadProgress = 0
        invalidateMicrophoneCheck()
        resetRecordingAudioFeedback()
        refreshPermissionStatus()
        resetWriterState()
        compositor.reset()
        hideCameraPreview()
    }

    func runMicrophoneCheckManually() async {
        _ = await runMicrophoneCheck(force: true, keepSessionRunningOnSuccess: false)
    }

    // MARK: - Sample buffer handlers

    private func handleScreenFrame(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self,
                  let writer = self.assetWriter,
                  let input = self.videoInput else { return }

            guard writer.status != .failed, writer.status != .cancelled else { return }

            if self.firstScreenPTS == nil {
                self.firstScreenPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            }

            if !self.sessionStarted {
                self.pendingScreenSamples.append(sampleBuffer)
                self.tryStartSessionIfReady(writer: writer)
                return
            }

            self.appendScreenSample(sampleBuffer, writer: writer, input: input)
        }
    }

    private func handleSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        _ = sampleBuffer
    }

    private func handleMicAudio(_ sampleBuffer: CMSampleBuffer) {
        updateMicrophoneMonitoring(with: sampleBuffer)
        handleAudioSample(sampleBuffer)
    }

    private func handleAudioSample(_ sampleBuffer: CMSampleBuffer) {
        writerQueue.async { [weak self] in
            guard let self,
                  let writer = self.assetWriter,
                  let input = self.audioInput else { return }

            guard writer.status != .failed, writer.status != .cancelled else { return }

            if self.firstAudioPTS == nil {
                self.firstAudioPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            }

            if !self.sessionStarted {
                self.pendingAudioSamples.append(sampleBuffer)
                self.tryStartSessionIfReady(writer: writer)
                return
            }

            self.appendAudioSample(sampleBuffer, writer: writer, input: input)
        }
    }

    private func tryStartSessionIfReady(writer: AVAssetWriter) {
        guard !sessionStarted else { return }
        guard let firstScreen = pendingScreenSamples.first else {
            return
        }

        let screenPTS = CMSampleBufferGetPresentationTimeStamp(firstScreen)

        guard writer.startWriting() else { return }
        writer.startSession(atSourceTime: screenPTS)
        sessionStarted = true
        sessionStartTime = screenPTS

        flushPendingSamples(writer: writer)
    }

    private func flushPendingSamples(writer: AVAssetWriter) {
        guard sessionStarted else { return }

        let bufferedSamples =
            pendingScreenSamples.map { (kind: BufferedSampleKind.screen, sample: $0) } +
            pendingAudioSamples.map { (kind: BufferedSampleKind.audio, sample: $0) }

        pendingScreenSamples.removeAll()
        pendingAudioSamples.removeAll()

        for buffered in bufferedSamples.sorted(by: {
            CMSampleBufferGetPresentationTimeStamp($0.sample) < CMSampleBufferGetPresentationTimeStamp($1.sample)
        }) {
            switch buffered.kind {
            case .screen:
                guard let input = videoInput else { continue }
                appendScreenSample(buffered.sample, writer: writer, input: input)
            case .audio:
                guard let input = audioInput else { continue }
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

        guard let retimedSample = retimedMicSampleBuffer(sampleBuffer) else { return }
        guard input.append(retimedSample) else { return }

        hasWrittenAudioSamples = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recordingAudioStatus = .live("Recording microphone audio from \(self.selectedMicrophoneName).")
        }
    }

    private func retimedMicSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let firstScreenPTS, let firstAudioPTS else {
            return sampleBuffer
        }

        let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard sampleCount > 0 else { return sampleBuffer }

        var timingInfo = Array(
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: sampleCount
        )

        let status = CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: sampleCount,
            arrayToFill: &timingInfo,
            entriesNeededOut: nil
        )

        guard status == noErr else { return sampleBuffer }

        let offset = CMTimeSubtract(firstScreenPTS, firstAudioPTS)
        let updatedTiming = timingInfo.map { info in
            CMSampleTimingInfo(
                duration: info.duration,
                presentationTimeStamp: CMTimeAdd(info.presentationTimeStamp, offset),
                decodeTimeStamp: info.decodeTimeStamp.isValid ? CMTimeAdd(info.decodeTimeStamp, offset) : info.decodeTimeStamp
            )
        }

        var adjustedSampleBuffer: CMSampleBuffer?
        let copyStatus = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: updatedTiming.count,
            sampleTimingArray: updatedTiming,
            sampleBufferOut: &adjustedSampleBuffer
        )

        guard copyStatus == noErr else { return sampleBuffer }
        return adjustedSampleBuffer
    }

    private func resetWriterState() {
        sessionStarted = false
        sessionStartTime = nil
        pendingScreenSamples.removeAll()
        pendingAudioSamples.removeAll()
        firstScreenPTS = nil
        firstAudioPTS = nil
        hasWrittenAudioSamples = false
    }

    private func configureCaptureCallbacks() {
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
    }

    private func runMicrophoneCheckIfNeeded() async -> Bool {
        if let lastVerifiedMicrophoneSignalAt,
           Date().timeIntervalSince(lastVerifiedMicrophoneSignalAt) < 30 {
            return true
        }

        return await runMicrophoneCheck(force: false, keepSessionRunningOnSuccess: true)
    }

    private func runMicrophoneCheck(force: Bool, keepSessionRunningOnSuccess: Bool) async -> Bool {
        if isRunningMicrophoneCheck {
            return false
        }

        if !force,
           let lastVerifiedMicrophoneSignalAt,
           Date().timeIntervalSince(lastVerifiedMicrophoneSignalAt) < 30 {
            return true
        }

        let granted = await cameraCapturer.requestMicrophonePermission()
        guard granted else {
            await MainActor.run {
                microphoneCheckState = .failed("Microphone permission is required.")
                microphoneLevel = 0
            }
            return false
        }

        isRunningMicrophoneCheck = true
        await MainActor.run {
            microphoneCheckState = .checking
            microphoneLevel = 0
        }

        do {
            try restartCameraSession(
                microphone: selectedMicrophone,
                includeCamera: false,
                includeMicrophone: true
            )

            let timeoutAt = Date().addingTimeInterval(3)
            var detected = false

            while Date() < timeoutAt {
                if let lastVerifiedMicrophoneSignalAt,
                   Date().timeIntervalSince(lastVerifiedMicrophoneSignalAt) < 1.5 {
                    detected = true
                    break
                }

                try? await Task.sleep(for: .milliseconds(100))
            }

            if !keepSessionRunningOnSuccess && !isRecording {
                cameraCapturer.stopCapture(waitUntilStopped: true)
            }

            let didDetect = detected
            await MainActor.run {
                microphoneCheckState = didDetect
                    ? .ready
                    : .failed("We couldn't hear this microphone. Speak a bit louder or choose another input, then test again.")
                if !didDetect {
                    microphoneLevel = 0
                }
            }

            isRunningMicrophoneCheck = false
            await MainActor.run { restorePreviewIfVisible() }
            return didDetect
        } catch {
            if !isRecording {
                cameraCapturer.stopCapture(waitUntilStopped: true)
            }

            await MainActor.run {
                microphoneCheckState = .failed("Mic check failed: \(error.localizedDescription)")
                microphoneLevel = 0
            }
            isRunningMicrophoneCheck = false
            await MainActor.run { restorePreviewIfVisible() }
            return false
        }
    }

    private func updateMicrophoneMonitoring(with sampleBuffer: CMSampleBuffer) {
        guard let level = audioLevel(from: sampleBuffer) else { return }

        let detectionThreshold = 0.006
        if level >= detectionThreshold {
            lastVerifiedMicrophoneSignalAt = Date()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let normalizedLevel = self.normalizedDisplayLevel(from: level)
            self.microphoneLevel = self.smoothedMeterLevel(current: self.microphoneLevel, incoming: normalizedLevel)

            if self.assetWriter != nil {
                self.recordingAudioLevel = self.smoothedMeterLevel(
                    current: self.recordingAudioLevel,
                    incoming: normalizedLevel
                )
                if level >= detectionThreshold {
                    self.recordingAudioStatus = .live("Recording microphone audio from \(self.selectedMicrophoneName).")
                }
            }
        }
    }

    private func audioLevel(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr,
              let dataPointer,
              length > 0 else {
            return nil
        }

        let asbd = streamDescription.pointee
        let formatFlags = asbd.mFormatFlags
        let isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0

        if isFloat && asbd.mBitsPerChannel == 32 {
            let sampleCount = length / MemoryLayout<Float>.size
            guard sampleCount > 0 else { return nil }
            let samples = dataPointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { pointer in
                Array(UnsafeBufferPointer(start: pointer, count: sampleCount))
            }
            return rmsLevel(samples)
        }

        if asbd.mBitsPerChannel == 16 {
            let sampleCount = length / MemoryLayout<Int16>.size
            guard sampleCount > 0 else { return nil }
            let samples = dataPointer.withMemoryRebound(to: Int16.self, capacity: sampleCount) { pointer in
                Array(UnsafeBufferPointer(start: pointer, count: sampleCount))
            }
            return rmsLevel(samples.map { Double($0) / Double(Int16.max) })
        }

        return nil
    }

    private func rmsLevel(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            let value = Double(sample)
            return partial + (value * value)
        } / Double(samples.count)
        return sqrt(meanSquare)
    }

    private func rmsLevel(_ samples: [Double]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + (sample * sample)
        } / Double(samples.count)
        return sqrt(meanSquare)
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

    private func refreshPreviewCaptureDevicesIfNeeded() {
        guard permissionsReady, !isRecording, !isRunningMicrophoneCheck else { return }

        if floatingCameraWindowController.isVisible {
            restorePreviewIfVisible()
            return
        }

        do {
            try restartCameraSession(
                camera: selectedCamera,
                microphone: selectedMicrophone,
                includeCamera: true,
                includeMicrophone: true
            )
        } catch {
            state = .error("Failed to switch capture device: \(error.localizedDescription)")
        }
    }

    private func restorePreviewIfVisible() {
        guard permissionsReady, !isRecording, !isRunningMicrophoneCheck, floatingCameraWindowController.isVisible else {
            return
        }

        previewRefreshTask?.cancel()
        previewRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.showCameraPreview(for: self.selectedDisplay)
        }
    }

    private func syncSelections() {
        if selectedDisplayID == nil || !availableDisplays.contains(where: { $0.displayID == selectedDisplayID }) {
            selectedDisplayID = availableDisplays.first?.displayID
        }
        if selectedCameraID == nil || !availableCameras.contains(where: { $0.uniqueID == selectedCameraID }) {
            selectedCameraID = availableCameras.first?.uniqueID
        }
        if selectedMicrophoneID == nil || !availableMicrophones.contains(where: { $0.uniqueID == selectedMicrophoneID }) {
            selectedMicrophoneID = availableMicrophones.first?.uniqueID
        }
    }

    private func invalidateMicrophoneCheck() {
        microphoneCheckState = .idle
        microphoneLevel = 0
        lastVerifiedMicrophoneSignalAt = nil
    }

    private func resetRecordingAudioFeedback() {
        recordingAudioStatus = .idle
        recordingAudioLevel = 0
    }

    private func normalizedDisplayLevel(from rawLevel: Double) -> Double {
        let noiseFloor = 0.005
        let fullScaleLevel = 0.10

        guard rawLevel > noiseFloor else { return 0 }

        let normalized = min(max((rawLevel - noiseFloor) / (fullScaleLevel - noiseFloor), 0), 1)
        return pow(normalized, 0.5)
    }

    private func smoothedMeterLevel(current: Double, incoming: Double) -> Double {
        let attack: Double = 0.35
        let release: Double = 0.18
        let factor = incoming > current ? attack : release
        return (current * (1 - factor)) + (incoming * factor)
    }

    private func restartCameraSession(
        camera: AVCaptureDevice? = nil,
        microphone: AVCaptureDevice? = nil,
        includeCamera: Bool,
        includeMicrophone: Bool
    ) throws {
        if cameraCapturer.session.isRunning {
            cameraCapturer.stopCapture(waitUntilStopped: true)
        }

        try cameraCapturer.setupSession(
            camera: camera,
            microphone: microphone,
            includeCamera: includeCamera,
            includeMicrophone: includeMicrophone
        )

        // Start synchronously so the session is fully running before the
        // preview or recorder relies on the newly selected device.
        cameraCapturer.startCapture(waitUntilRunning: true)
    }

    private func validateSavedRecordingAudio(at url: URL) async {
        let asset = AVURLAsset(url: url)

        let audioTracks: [AVAssetTrack]
        do {
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            await MainActor.run {
                recordingAudioStatus = .failed("Saved video, but audio validation failed: \(error.localizedDescription)")
            }
            return
        }

        guard !audioTracks.isEmpty else {
            await MainActor.run {
                recordingAudioStatus = .failed("Saved video, but no audio track was found.")
            }
            return
        }

        var hasUsableAudio = false
        for track in audioTracks {
            guard let timeRange = try? await track.load(.timeRange) else { continue }
            let duration = timeRange.duration.seconds
            if duration.isFinite && duration > 0.1 {
                hasUsableAudio = true
                break
            }
        }

        let validatedAudioTrack = hasUsableAudio

        await MainActor.run {
            if validatedAudioTrack && hasWrittenAudioSamples {
                recordingAudioStatus = .validated("Saved video includes microphone audio from \(selectedMicrophoneName).")
            } else if validatedAudioTrack {
                recordingAudioStatus = .validated("Saved video includes an audio track.")
            } else {
                recordingAudioStatus = .failed("Saved video, but the audio track looks empty.")
            }
        }
    }
}
