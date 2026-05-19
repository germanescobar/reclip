import AppKit
import SwiftUI

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let manager: RecordingManager
    private let onComplete: () -> Void

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(manager: RecordingManager, onComplete: @escaping () -> Void) {
        self.manager = manager
        self.onComplete = onComplete
    }

    func show() {
        NSApp.setActivationPolicy(.regular)

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(manager: manager) { [weak self] in
            self?.close()
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Reclip"
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        onComplete()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
