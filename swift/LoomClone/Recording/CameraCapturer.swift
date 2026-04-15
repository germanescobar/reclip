import Foundation
import AVFoundation

class CameraCapturer: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.loomclone.camera.session")
    private let videoQueue = DispatchQueue(label: "com.loomclone.camera.video")
    private let audioQueue = DispatchQueue(label: "com.loomclone.camera.audio")
    private var isConfigured = false

    var onCameraFrame: ((CMSampleBuffer) -> Void)?
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
            session.sessionPreset = .medium

            do {
                if includeCamera {
                    let cam = camera ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                    guard let cam else { throw CameraError.noCameraFound }
                    let videoInput = try AVCaptureDeviceInput(device: cam)
                    guard session.canAddInput(videoInput) else { throw CameraError.cannotAddCameraInput }
                    session.addInput(videoInput)
                }

                if includeMicrophone {
                    let mic = microphone ?? AVCaptureDevice.default(for: .audio)
                    guard let mic else { throw CameraError.noMicrophoneFound }
                    let audioInput = try AVCaptureDeviceInput(device: mic)
                    guard session.canAddInput(audioInput) else { throw CameraError.cannotAddMicrophoneInput }
                    session.addInput(audioInput)
                }

                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
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

    func startCapture() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
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
