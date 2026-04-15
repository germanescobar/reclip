import AppKit

final class RecordingHUDWindowController: NSObject, NSWindowDelegate {
    private enum Layout {
        static let size = CGSize(width: 74, height: 188)
        static let topInset: CGFloat = 28
        static let trailingInset: CGFloat = 28
    }

    private var panel: RecordingHUDPanel?
    private var displayFrame: CGRect = .zero
    private var preferredOrigin: CGPoint?
    private let contentView = RecordingHUDContentView(frame: CGRect(origin: .zero, size: Layout.size))

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func show(
        on screen: NSScreen,
        durationText: String,
        audioLevel: Double,
        onStop: @escaping () -> Void
    ) {
        displayFrame = screen.visibleFrame

        let panel = makePanelIfNeeded()
        contentView.update(
            durationText: durationText,
            audioLevel: audioLevel,
            onStop: onStop
        )
        panel.setFrame(panelFrame(), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> RecordingHUDPanel {
        if let panel {
            return panel
        }

        let panel = RecordingHUDPanel(
            contentRect: CGRect(origin: .zero, size: Layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.sharingType = .none
        panel.contentView = contentView

        self.panel = panel
        return panel
    }

    private func panelFrame() -> CGRect {
        let defaultFrame = CGRect(
            x: displayFrame.maxX - Layout.size.width - Layout.trailingInset,
            y: displayFrame.maxY - Layout.size.height - Layout.topInset,
            width: Layout.size.width,
            height: Layout.size.height
        )

        guard let preferredOrigin else {
            return defaultFrame
        }

        return clamp(frame: CGRect(origin: preferredOrigin, size: Layout.size))
    }

    private func clamp(frame: CGRect) -> CGRect {
        let minX = displayFrame.minX
        let maxX = displayFrame.maxX - frame.width
        let minY = displayFrame.minY
        let maxY = displayFrame.maxY - frame.height

        let origin = CGPoint(
            x: min(max(frame.origin.x, minX), maxX),
            y: min(max(frame.origin.y, minY), maxY)
        )

        return CGRect(origin: origin, size: frame.size)
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel else { return }
        let clampedFrame = clamp(frame: panel.frame)
        if clampedFrame.origin != panel.frame.origin {
            panel.setFrame(clampedFrame, display: true)
        }
        preferredOrigin = clampedFrame.origin
    }
}

private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class RecordingHUDContentView: NSView {
    private let backgroundView = NSVisualEffectView()
    private let dragHandle = DragHandleView()
    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let levelView = AudioLevelView(frame: .zero)
    private let stopButton = NSButton()

    private var stopAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        backgroundView.frame = bounds
        dragHandle.frame = CGRect(x: 19, y: bounds.height - 20, width: bounds.width - 38, height: 8)
        timerLabel.frame = CGRect(x: 10, y: bounds.height - 48, width: bounds.width - 20, height: 18)
        levelView.frame = CGRect(x: 19, y: 62, width: bounds.width - 38, height: 64)
        stopButton.frame = CGRect(x: 17, y: 14, width: bounds.width - 34, height: 34)
    }

    func update(
        durationText: String,
        audioLevel: Double,
        onStop: @escaping () -> Void
    ) {
        timerLabel.stringValue = durationText
        levelView.level = audioLevel
        stopAction = onStop
        needsLayout = true
    }

    @objc private func stopButtonPressed() {
        stopAction?()
    }

    private func setupView() {
        wantsLayer = true

        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 22
        backgroundView.layer?.masksToBounds = true
        addSubview(backgroundView)

        dragHandle.wantsLayer = true
        dragHandle.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.26).cgColor
        dragHandle.layer?.cornerRadius = 4
        addSubview(dragHandle)

        timerLabel.alignment = .center
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timerLabel.textColor = .white
        addSubview(timerLabel)

        levelView.wantsLayer = true
        addSubview(levelView)

        stopButton.title = ""
        stopButton.isBordered = false
        stopButton.bezelStyle = .regularSquare
        stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop recording")
        stopButton.contentTintColor = .white
        stopButton.target = self
        stopButton.action = #selector(stopButtonPressed)
        stopButton.wantsLayer = true
        stopButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.94).cgColor
        stopButton.layer?.cornerRadius = 17
        stopButton.imageScaling = .scaleProportionallyDown
        addSubview(stopButton)
    }

}

private final class DragHandleView: NSView {
    private var dragOrigin: NSPoint = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let current = event.locationInWindow
        let delta = NSPoint(x: current.x - dragOrigin.x, y: current.y - dragOrigin.y)
        var origin = window.frame.origin
        origin.x += delta.x
        origin.y += delta.y
        window.setFrameOrigin(origin)
    }
}

private final class AudioLevelView: NSView {
    var level: Double = 0 {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let outerPath = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.14).setFill()
        outerPath.fill()

        let insetRect = bounds.insetBy(dx: 5, dy: 5)
        let fillHeight = max(insetRect.height * level, level > 0 ? 8 : 0)
        let fillRect = CGRect(
            x: insetRect.minX,
            y: insetRect.minY,
            width: insetRect.width,
            height: min(fillHeight, insetRect.height)
        )

        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 7, yRadius: 7)
        meterColor.setFill()
        fillPath.fill()
    }

    private var meterColor: NSColor {
        if level > 0.52 {
            return .systemGreen
        }
        if level > 0.18 {
            return .systemYellow
        }
        return .systemBlue
    }
}
