import Foundation
import AVFoundation

class CameraCapturer: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.loomclone.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.loomclone.camera.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "com.loomclone.camera.audio", qos: .userInitiated)
    private var isConfigured = false

    var onCameraFrame: ((CMSampleBuffer) -> Void)?
    var onCameraFrameDropped: ((String) -> Void)?
    var onMicAudio: ((CMSampleBuffer) -> Void)?

    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func availableMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    func cameraPermissionStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func microphonePermissionStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    func hasCameraPermission() -> Bool {
        cameraPermissionStatus() == .authorized
    }

    func hasMicrophonePermission() -> Bool {
        microphonePermissionStatus() == .authorized
    }

    func requestCameraPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func requestPermissions() async -> Bool {
        let videoGranted = await requestCameraPermission()
        let audioGranted = await requestMicrophonePermission()
        return videoGranted && audioGranted
    }

    func setupSession(
        camera: AVCaptureDevice? = nil,
        microphone: AVCaptureDevice? = nil,
        includeCamera: Bool = true,
        includeMicrophone: Bool = true
    ) throws {
        var thrownError: Error?

        sessionQueue.sync {
            if isConfigured {
                // Reconfigure with new devices
                session.beginConfiguration()
                defer { session.commitConfiguration() }

                // Remove existing inputs one at a time to avoid
                // "mutated while being enumerated" when the preview layer
                // concurrently accesses the session's internal arrays.
                while let input = session.inputs.first {
                    session.removeInput(input)
                }

                do {
                    if includeCamera {
                        let cam = camera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                        guard let cam else { throw CameraError.noCameraFound }
                        let videoInput = try AVCaptureDeviceInput(device: cam)
                        guard session.canAddInput(videoInput) else { throw CameraError.cannotAddCameraInput }
                        session.addInput(videoInput)
                        Self.lockCameraFormat(cam)
                    }

                    if includeMicrophone {
                        let mic = microphone ?? AVCaptureDevice.default(for: .audio)
                        guard let mic else { throw CameraError.noMicrophoneFound }
                        let audioInput = try AVCaptureDeviceInput(device: mic)
                        guard session.canAddInput(audioInput) else { throw CameraError.cannotAddMicrophoneInput }
                        session.addInput(audioInput)
                    }
                } catch {
                    thrownError = error
                }
                return
            }

            session.beginConfiguration()
            defer { session.commitConfiguration() }
            // No session preset: the camera's activeFormat is pinned explicitly
            // after the input is added. Preset negotiation put some UVC webcams
            // into modes that run seconds behind the sensor.

            do {
                if includeCamera {
                    let cam = camera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                    guard let cam else { throw CameraError.noCameraFound }
                    let videoInput = try AVCaptureDeviceInput(device: cam)
                    guard session.canAddInput(videoInput) else { throw CameraError.cannotAddCameraInput }
                    session.addInput(videoInput)
                    Self.lockCameraFormat(cam)
                }

                if includeMicrophone {
                    let mic = microphone ?? AVCaptureDevice.default(for: .audio)
                    guard let mic else { throw CameraError.noMicrophoneFound }
                    let audioInput = try AVCaptureDeviceInput(device: mic)
                    guard session.canAddInput(audioInput) else { throw CameraError.cannotAddMicrophoneInput }
                    session.addInput(audioInput)
                }

                // Deliver frames in the camera's native format: forcing BGRA adds
                // a per-frame conversion in the capture pipeline that can starve
                // delivery under load, and Core Image reads the native format.
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                if session.canAddOutput(videoOutput) {
                    session.addOutput(videoOutput)
                }

                audioOutput.setSampleBufferDelegate(self, queue: audioQueue)
                if session.canAddOutput(audioOutput) {
                    session.addOutput(audioOutput)
                }

                isConfigured = true
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
    }

    /// Pins an explicit device format (~VGA at 30fps) instead of relying on
    /// session-preset negotiation. The overlay bubble only needs ~200px, and
    /// preset-negotiated modes on some UVC webcams run seconds behind the
    /// sensor.
    private static func lockCameraFormat(_ device: AVCaptureDevice) {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return dims.width >= 640 && dims.height >= 480 &&
                format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }

        let chosen = candidates.min { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
        }

        guard let chosen else {
            avSyncLog("camera: no >=640x480@30 format found; keeping \(device.activeFormat)")
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = chosen
            // Target 30fps, clamped into the range's own duration bounds:
            // DAL/USB cameras throw on durations outside the supported range,
            // and the range minimum would pin 60fps+ modes to their maximum
            // rate, far above what the 30fps compositing pipeline needs.
            if let range = chosen.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }) {
                var duration = CMTime(value: 1, timescale: 30)
                if CMTimeCompare(duration, range.minFrameDuration) < 0 {
                    duration = range.minFrameDuration
                }
                if CMTimeCompare(duration, range.maxFrameDuration) > 0 {
                    duration = range.maxFrameDuration
                }
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
            device.unlockForConfiguration()
            avSyncLog("camera: locked format \(chosen)")
        } catch {
            avSyncLog("camera: failed to lock format: \(error.localizedDescription)")
        }
    }

    func startCapture(waitUntilRunning: Bool = false) {
        let startWork = {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }

        if waitUntilRunning {
            sessionQueue.sync(execute: startWork)
        } else {
            sessionQueue.async(execute: startWork)
        }
    }

    func stopCapture(waitUntilStopped: Bool = false) {
        let stopWork = {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }

        if waitUntilStopped {
            sessionQueue.sync(execute: stopWork)
        } else {
            sessionQueue.async(execute: stopWork)
        }
    }
}

extension CameraCapturer: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard sampleBuffer.isValid else { return }

        if output == videoOutput {
            onCameraFrame?(sampleBuffer)
        } else if output == audioOutput {
            onMicAudio?(sampleBuffer)
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard output == videoOutput else { return }
        let reason = CMGetAttachment(
            sampleBuffer,
            key: kCMSampleBufferAttachmentKey_DroppedFrameReason,
            attachmentModeOut: nil
        ) as? String ?? "unknown"
        onCameraFrameDropped?(reason)
    }
}

enum CameraError: LocalizedError {
    case noCameraFound
    case noMicrophoneFound
    case cannotAddCameraInput
    case cannotAddMicrophoneInput

    var errorDescription: String? {
        switch self {
        case .noCameraFound: return "No camera found"
        case .noMicrophoneFound: return "No microphone found"
        case .cannotAddCameraInput: return "Failed to add the selected camera to the capture session"
        case .cannotAddMicrophoneInput: return "Failed to add the selected microphone to the capture session"
        }
    }
}
