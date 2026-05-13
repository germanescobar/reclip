import AppKit
import SwiftUI

final class PostRecordingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var manager: RecordingManager?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show(fileURL: URL, manager: RecordingManager) {
        self.manager = manager
        let view = PostRecordingView(fileURL: fileURL, manager: manager) { [weak self] in
            self?.close()
        }

        NSApp.setActivationPolicy(.regular)

        if let window {
            window.contentView = NSHostingView(rootView: view)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 900, height: 580),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review Recording"
        window.center()
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: view)

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        manager?.reset()
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        manager?.reset()
        NSApp.setActivationPolicy(.accessory)
    }
}
