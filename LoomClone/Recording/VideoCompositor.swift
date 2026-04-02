import Foundation
import CoreImage
import CoreVideo
import AVFoundation
import Metal

class VideoCompositor: @unchecked Sendable {
    private let ciContext: CIContext
    private var pixelBufferPool: CVPixelBufferPool?
    private var poolWidth: Int?
    private var poolHeight: Int?
    private let lock = NSLock()
    private var _latestCameraBuffer: CVPixelBuffer?
    private var _overlayNormalizedCenter = CGPoint(x: 0.85, y: 0.2)
    private let overlaySize: CGFloat = 200

    var latestCameraBuffer: CVPixelBuffer? {
        get { lock.withLock { _latestCameraBuffer } }
        set { lock.withLock { _latestCameraBuffer = newValue } }
    }

    var overlayNormalizedCenter: CGPoint {
        get { lock.withLock { _overlayNormalizedCenter } }
        set {
            lock.withLock {
                _overlayNormalizedCenter = CGPoint(
                    x: min(max(newValue.x, 0), 1),
                    y: min(max(newValue.y, 0), 1)
                )
            }
        }
    }

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is required for the video compositor")
        }
        ciContext = CIContext(mtlDevice: device)
    }

    func updateCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestCameraBuffer = pixelBuffer
    }

    func reset() {
        latestCameraBuffer = nil
        overlayNormalizedCenter = CGPoint(x: 0.85, y: 0.2)
        pixelBufferPool = nil
        poolWidth = nil
        poolHeight = nil
    }

    func compositeFrame(_ screenBuffer: CMSampleBuffer, width: Int, height: Int) -> CMSampleBuffer? {
        guard let screenPixelBuffer = CMSampleBufferGetImageBuffer(screenBuffer) else { return nil }

        let screenImage = CIImage(cvPixelBuffer: screenPixelBuffer)
        var outputImage = screenImage

        if let cameraPixelBuffer = latestCameraBuffer {
            let cameraImage = CIImage(cvPixelBuffer: cameraPixelBuffer)
            if let overlayImage = createCircularOverlay(
                cameraImage: cameraImage,
                screenWidth: CGFloat(width),
                screenHeight: CGFloat(height)
            ) {
                outputImage = overlayImage.composited(over: screenImage)
            }
        }

        // Get or create pixel buffer pool
        if pixelBufferPool == nil || poolWidth != width || poolHeight != height {
            pixelBufferPool = createPixelBufferPool(width: width, height: height)
            poolWidth = width
            poolHeight = height
        }

        guard let pool = pixelBufferPool else { return nil }

        var outputPixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputPixelBuffer)
        guard status == kCVReturnSuccess, let outputBuffer = outputPixelBuffer else { return nil }

        ciContext.render(outputImage, to: outputBuffer)

        return createSampleBuffer(from: outputBuffer, timing: screenBuffer)
    }

    private func createCircularOverlay(cameraImage: CIImage, screenWidth: CGFloat, screenHeight: CGFloat) -> CIImage? {
        let cameraExtent = cameraImage.extent
        guard cameraExtent.width > 0, cameraExtent.height > 0 else { return nil }

        // Scale camera to overlay size
        let scale = overlaySize / min(cameraExtent.width, cameraExtent.height)
        let scaledCamera = cameraImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let scaledExtent = scaledCamera.extent

        // Center-crop to square
        let cropSize = min(scaledExtent.width, scaledExtent.height)
        let cropRect = CGRect(
            x: scaledExtent.midX - cropSize / 2,
            y: scaledExtent.midY - cropSize / 2,
            width: cropSize,
            height: cropSize
        )
        let croppedCamera = scaledCamera.cropped(to: cropRect)

        // Create circular mask using radial gradient
        let radius = cropSize / 2
        let centerX = cropRect.midX
        let centerY = cropRect.midY

        let radialGradient = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: centerX, y: centerY),
            "inputRadius0": radius - 2,  // Slight feathering
            "inputRadius1": radius,
            "inputColor0": CIColor.white,
            "inputColor1": CIColor.clear
        ])!

        guard let maskImage = radialGradient.outputImage?.cropped(to: cropRect) else { return nil }

        // Apply mask to camera
        let blended = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: croppedCamera,
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: maskImage
        ])!

        guard let maskedCamera = blended.outputImage else { return nil }

        let clampedCenter = overlayCenter(
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            overlaySize: cropSize
        )

        let xOffset = clampedCenter.x - cropRect.midX
        let yOffset = clampedCenter.y - cropRect.midY
        let positioned = maskedCamera.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))

        return positioned
    }

    private func overlayCenter(screenWidth: CGFloat, screenHeight: CGFloat, overlaySize: CGFloat) -> CGPoint {
        let normalizedCenter = overlayNormalizedCenter
        let minX = overlaySize / 2
        let maxX = screenWidth - overlaySize / 2
        let minY = overlaySize / 2
        let maxY = screenHeight - overlaySize / 2

        return CGPoint(
            x: min(max(normalizedCenter.x * screenWidth, minX), maxX),
            y: min(max(normalizedCenter.y * screenHeight, minY), maxY)
        )
    }

    private func createPixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        return pool
    }

    private func createSampleBuffer(from pixelBuffer: CVPixelBuffer, timing sourceSample: CMSampleBuffer) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sourceSample, at: 0, timingInfoOut: &timingInfo)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription)

        guard let desc = formatDescription else { return nil }

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescription: desc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        return sampleBuffer
    }
}
