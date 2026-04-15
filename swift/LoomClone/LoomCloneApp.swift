import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let manager = RecordingManager()
    let authManager = AuthManager()

    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let recordingHUDWindowController = RecordingHUDWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        manager.onRecordingChanged = { [weak self] isRecording in
            DispatchQueue.main.async {
                self?.updateStatusItemAppearance(isRecording: isRecording)
                self?.updateRecordingHUD()
            }
        }
        manager.onStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                guard case .preparing = state else { return }
                self?.closePopover()
            }
        }
        manager.onRecordingMetricsChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusItemAppearance(isRecording: self?.manager.isRecording == true)
                self?.updateRecordingHUD()
            }
        }

        configureStatusItem()
        configurePopover()
        updateStatusItemAppearance(isRecording: manager.isRecording)
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
            button.imagePosition = .imageLeading
        }
    }

    private func configurePopover() {
        popover.delegate = self
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: ContentView(manager: manager, authManager: authManager)
        )
    }

    private func showPopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        refreshCameraPreview()
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func updateStatusItemAppearance(isRecording: Bool) {
        let imageName = isRecording ? "record.circle.fill" : "record.circle"
        guard let button = statusItem.button else { return }

        button.image = NSImage(
            systemSymbolName: imageName,
            accessibilityDescription: "Reclip"
        )

        if isRecording {
            button.title = ""
            button.toolTip = "Recording in progress"
        } else {
            button.title = ""
            button.toolTip = "Reclip"
        }
    }

    private func refreshCameraPreview() {
        guard popover.isShown, manager.permissionsReady else { return }
        Task { [manager] in
            await manager.showCameraPreview(for: manager.selectedDisplay)
        }
    }

    private func updateRecordingHUD() {
        guard manager.isRecording else {
            if recordingHUDWindowController.isVisible {
                recordingHUDWindowController.hide()
                showPopover(nil)
            }
            return
        }

        guard let screen = screenForCurrentRecording() else {
            recordingHUDWindowController.hide()
            return
        }

        recordingHUDWindowController.show(
            on: screen,
            durationText: statusItemDurationText(),
            audioLevel: manager.recordingAudioLevel
        ) { [weak self] in
            Task {
                await self?.manager.stopRecording()
            }
        }
    }

    private func screenForCurrentRecording() -> NSScreen? {
        guard let displayID = manager.selectedDisplay?.displayID else {
            return NSScreen.main ?? NSScreen.screens.first
        }

        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == displayID
        } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func statusItemDurationText() -> String {
        let mins = Int(manager.recordingDuration) / 60
        let secs = Int(manager.recordingDuration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }


    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            authManager.handleCallback(url: url)
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
