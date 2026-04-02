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

    func requestPermissions() async -> Bool {
        let videoGranted = await AVCaptureDevice.requestAccess(for: .video)
        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        return videoGranted && audioGranted
    }

    func setupSession() throws {
        var thrownError: Error?

        sessionQueue.sync {
            guard !isConfigured else { return }

            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .medium

            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) else {
                    throw CameraError.noCameraFound
                }
                let videoInput = try AVCaptureDeviceInput(device: camera)
                if session.canAddInput(videoInput) {
                    session.addInput(videoInput)
                }

                guard let mic = AVCaptureDevice.default(for: .audio) else {
                    throw CameraError.noMicrophoneFound
                }
                let audioInput = try AVCaptureDeviceInput(device: mic)
                if session.canAddInput(audioInput) {
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

    func stopCapture() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
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

    var errorDescription: String? {
        switch self {
        case .noCameraFound: return "No camera found"
        case .noMicrophoneFound: return "No microphone found"
        }
    }
}
