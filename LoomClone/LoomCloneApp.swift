import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let manager = RecordingManager()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        manager.onRecordingChanged = { [weak self] isRecording in
            DispatchQueue.main.async {
                self?.updateStatusItemIcon(isRecording: isRecording)
            }
        }

        configureStatusItem()
        configurePopover()
        updateStatusItemIcon(isRecording: manager.isRecording)
        manager.onDisplaysLoaded = { [weak self] in
            self?.refreshCameraPreview()
        }

        DispatchQueue.main.async { [weak self] in
            self?.showPopover(nil)
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(sender)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.imagePosition = .imageOnly
        }
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(manager: manager)
        )
    }

    private func showPopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        refreshCameraPreview()
    }

    private func updateStatusItemIcon(isRecording: Bool) {
        let imageName = isRecording ? "record.circle.fill" : "record.circle"
        statusItem.button?.image = NSImage(
            systemSymbolName: imageName,
            accessibilityDescription: "LoomClone"
        )
    }

    private func refreshCameraPreview() {
        guard popover.isShown else { return }
        Task { [manager] in
            await manager.showCameraPreview(for: manager.selectedDisplay)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        manager.hideCameraPreview()
    }
}

@main
struct LoomCloneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
