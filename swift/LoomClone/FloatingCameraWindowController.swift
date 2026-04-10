import AppKit
import AVFoundation
import SwiftUI

final class FloatingCameraWindowController: NSObject, NSWindowDelegate {
    static let previewSize: CGFloat = 160

    var onNormalizedCenterChanged: ((CGPoint) -> Void)?
    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private var panel: NSPanel?
    private var displayFrame: CGRect = .zero

    func show(captureSession: AVCaptureSession, on screen: NSScreen, normalizedCenter initialCenter: CGPoint) {
        displayFrame = screen.frame

        let panel = makePanelIfNeeded(captureSession: captureSession)
        panel.contentView = NSHostingView(
            rootView: FloatingCameraPreview(captureSession: captureSession)
        )
        panel.setFrame(panelFrame(for: initialCenter), display: true)
        panel.orderFrontRegardless()

        let clampedCenter = normalizedCenter(for: panel.frame)
        onNormalizedCenterChanged?(clampedCenter)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }

        let clampedFrame = clamp(frame: panel.frame)
        if clampedFrame.origin != panel.frame.origin {
            panel.setFrame(clampedFrame, display: true)
        }

        onNormalizedCenterChanged?(normalizedCenter(for: clampedFrame))
    }

    private func makePanelIfNeeded(captureSession: AVCaptureSession) -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: Self.previewSize, height: Self.previewSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        panel.contentView = NSHostingView(
            rootView: FloatingCameraPreview(captureSession: captureSession)
        )

        self.panel = panel
        return panel
    }

    private func panelFrame(for normalizedCenter: CGPoint) -> CGRect {
        let width = Self.previewSize
        let height = Self.previewSize
        let minX = displayFrame.minX
        let maxX = displayFrame.maxX - width
        let minY = displayFrame.minY
        let maxY = displayFrame.maxY - height

        let origin = CGPoint(
            x: min(max(displayFrame.minX + normalizedCenter.x * displayFrame.width - width / 2, minX), maxX),
            y: min(max(displayFrame.minY + normalizedCenter.y * displayFrame.height - height / 2, minY), maxY)
        )

        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    private func clamp(frame: CGRect) -> CGRect {
        let width = frame.width
        let height = frame.height
        let minX = displayFrame.minX
        let maxX = displayFrame.maxX - width
        let minY = displayFrame.minY
        let maxY = displayFrame.maxY - height

        let origin = CGPoint(
            x: min(max(frame.origin.x, minX), maxX),
            y: min(max(frame.origin.y, minY), maxY)
        )

        return CGRect(origin: origin, size: frame.size)
    }

    private func normalizedCenter(for frame: CGRect) -> CGPoint {
        CGPoint(
            x: (frame.midX - displayFrame.minX) / displayFrame.width,
            y: (frame.midY - displayFrame.minY) / displayFrame.height
        )
    }
}

private struct FloatingCameraPreview: View {
    let captureSession: AVCaptureSession

    var body: some View {
        CameraPreviewView(captureSession: captureSession)
            .frame(
                width: FloatingCameraWindowController.previewSize,
                height: FloatingCameraWindowController.previewSize
            )
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 3)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .background(Color.clear)
    }
}
