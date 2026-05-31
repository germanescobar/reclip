import AppKit
import CoreGraphics

enum CaptureRegionGeometry {
    static let minimumSize: CGFloat = 16

    static func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }

        return NSScreen.screens.first { screen in
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return screenNumber.uint32Value == displayID
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return number.uint32Value
    }

    static func sourceRect(fromScreenRect screenRect: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(
            x: screenRect.minX - screen.frame.minX,
            y: screen.frame.maxY - screenRect.maxY,
            width: screenRect.width,
            height: screenRect.height
        ).standardized
    }

    static func sourceRect(fromGlobalTopLeftRect topLeftRect: CGRect, on screen: NSScreen) -> CGRect {
        let displayFrame = topLeftDisplayFrame(for: screen)
        return CGRect(
            x: topLeftRect.minX - displayFrame.minX,
            y: topLeftRect.minY - displayFrame.minY,
            width: topLeftRect.width,
            height: topLeftRect.height
        ).standardized
    }

    static func topLeftDisplayFrame(for screen: NSScreen) -> CGRect {
        guard let displayID = displayID(for: screen) else {
            return CGRect(origin: .zero, size: screen.frame.size)
        }

        let bounds = CGDisplayBounds(displayID)
        return bounds
    }

    static func screenRect(fromSourceRect sourceRect: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.minX + sourceRect.minX,
            y: screen.frame.maxY - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        ).standardized
    }

    static func localSelectionRect(fromSourceRect sourceRect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: sourceRect.minX,
            y: bounds.height - sourceRect.maxY,
            width: sourceRect.width,
            height: sourceRect.height
        ).standardized
    }

    static func sourceRect(fromLocalSelectionRect localRect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: localRect.minX,
            y: bounds.height - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        ).standardized
    }
}

final class CaptureRegionOutlineController {
    private var panel: NSPanel?

    func show(sourceRect: CGRect, on screen: NSScreen) {
        let screenRect = CaptureRegionGeometry.screenRect(fromSourceRect: sourceRect, on: screen)
        guard screenRect.width >= CaptureRegionGeometry.minimumSize,
              screenRect.height >= CaptureRegionGeometry.minimumSize else {
            hide()
            return
        }

        let panel = makePanelIfNeeded()
        panel.setFrame(screenRect.insetBy(dx: -2, dy: -2), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel {
            return panel
        }

        let view = CaptureRegionOutlineView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let panel = NSPanel(
            contentRect: view.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        self.panel = panel
        return panel
    }
}

final class AreaSelectionWindowController {
    private var panel: NSPanel?

    func selectArea(
        on screen: NSScreen,
        initialSourceRect: CGRect,
        completion: @escaping (CGRect?) -> Void
    ) {
        let selectionView = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        selectionView.initialSourceRect = initialSourceRect
        selectionView.onCancel = { [weak self] in
            self?.panel?.orderOut(nil)
            completion(nil)
        }
        selectionView.onConfirm = { [weak self] localRect in
            self?.panel?.orderOut(nil)
            completion(CaptureRegionGeometry.sourceRect(fromLocalSelectionRect: localRect, in: selectionView.bounds))
        }

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = selectionView
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

private final class CaptureRegionOutlineView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 3, dy: 3)
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.lineWidth = 4
        path.stroke()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let innerPath = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
        innerPath.lineWidth = 1
        innerPath.stroke()
    }
}

private final class AreaSelectionView: NSView {
    enum ResizeCorner: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    enum DragMode {
        case none
        case creating(start: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(anchor: CGPoint)
    }

    var initialSourceRect: CGRect = .zero {
        didSet {
            selectionRect = CaptureRegionGeometry.localSelectionRect(fromSourceRect: initialSourceRect, in: bounds)
        }
    }
    var onCancel: (() -> Void)?
    var onConfirm: ((CGRect) -> Void)?

    private var selectionRect: CGRect = .zero {
        didSet {
            updateButtons()
            needsDisplay = true
        }
    }
    private var dragMode: DragMode = .none
    private let confirmButton = NSButton(title: "Confirm", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let buttonContainer = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupButtons()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupButtons()
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if selectionRect == .zero, initialSourceRect != .zero {
            selectionRect = CaptureRegionGeometry.localSelectionRect(fromSourceRect: initialSourceRect, in: bounds)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        guard hasValidSelection else { return }

        let overlayPath = NSBezierPath(rect: bounds)
        overlayPath.append(NSBezierPath(rect: selectionRect))
        overlayPath.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.34).setFill()
        overlayPath.fill()

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 3
        path.stroke()

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let innerPath = NSBezierPath(rect: selectionRect.insetBy(dx: 2, dy: 2))
        innerPath.lineWidth = 1
        innerPath.stroke()

        drawHandles()
    }

    override func mouseDown(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))

        if hasValidSelection, let corner = resizeCorner(at: point) {
            dragMode = .resizing(anchor: anchorPoint(for: corner))
        } else if hasValidSelection, selectionRect.contains(point) {
            dragMode = .moving(start: point, original: selectionRect)
        } else {
            dragMode = .creating(start: point)
            selectionRect = CGRect(origin: point, size: .zero)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))

        switch dragMode {
        case .none:
            return
        case .creating(let start):
            selectionRect = normalizedRect(from: start, to: point)
        case .moving(let start, let original):
            let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
            selectionRect = clamped(original.offsetBy(dx: delta.x, dy: delta.y))
        case .resizing(let anchor):
            selectionRect = normalizedRect(from: anchor, to: point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        dragMode = .none
        if !hasValidSelection {
            selectionRect = .zero
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    private var hasValidSelection: Bool {
        selectionRect.width >= CaptureRegionGeometry.minimumSize &&
        selectionRect.height >= CaptureRegionGeometry.minimumSize
    }

    private func setupButtons() {
        buttonContainer.material = .hudWindow
        buttonContainer.blendingMode = .withinWindow
        buttonContainer.state = .active
        buttonContainer.wantsLayer = true
        buttonContainer.layer?.cornerRadius = 8
        addSubview(buttonContainer)

        confirmButton.bezelStyle = .rounded
        confirmButton.target = self
        confirmButton.action = #selector(confirmSelection)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelSelection)

        buttonContainer.addSubview(cancelButton)
        buttonContainer.addSubview(confirmButton)
        updateButtons()
    }

    private func updateButtons() {
        buttonContainer.isHidden = !hasValidSelection
        guard hasValidSelection else { return }

        let containerSize = CGSize(width: 164, height: 42)
        let preferredOrigin = CGPoint(
            x: selectionRect.maxX - containerSize.width,
            y: selectionRect.minY - containerSize.height - 10
        )
        let origin = CGPoint(
            x: min(max(preferredOrigin.x, 12), bounds.width - containerSize.width - 12),
            y: min(max(preferredOrigin.y, 12), bounds.height - containerSize.height - 12)
        )
        buttonContainer.frame = CGRect(origin: origin, size: containerSize)
        cancelButton.frame = CGRect(x: 8, y: 8, width: 70, height: 26)
        confirmButton.frame = CGRect(x: 86, y: 8, width: 70, height: 26)
    }

    private func drawHandles() {
        for corner in ResizeCorner.allCases {
            let rect = visibleHandleRect(for: corner)
            NSColor.systemBlue.setFill()
            let handlePath = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
            handlePath.fill()
            NSColor.white.setStroke()
            handlePath.lineWidth = 1
            handlePath.stroke()
        }
    }

    private func resizeCorner(at point: CGPoint) -> ResizeCorner? {
        ResizeCorner.allCases.first { corner in
            hitHandleRect(for: corner).contains(point)
        }
    }

    private func anchorPoint(for corner: ResizeCorner) -> CGPoint {
        switch corner {
        case .topLeft:
            return CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
        case .topRight:
            return CGPoint(x: selectionRect.minX, y: selectionRect.minY)
        case .bottomLeft:
            return CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)
        case .bottomRight:
            return CGPoint(x: selectionRect.minX, y: selectionRect.maxY)
        }
    }

    private func visibleHandleRect(for corner: ResizeCorner) -> CGRect {
        handleRect(for: corner, size: 14)
    }

    private func hitHandleRect(for corner: ResizeCorner) -> CGRect {
        handleRect(for: corner, size: 36)
    }

    private func handleRect(for corner: ResizeCorner, size: CGFloat) -> CGRect {
        let center: CGPoint
        switch corner {
        case .topLeft:
            center = CGPoint(x: selectionRect.minX, y: selectionRect.maxY)
        case .topRight:
            center = CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)
        case .bottomLeft:
            center = CGPoint(x: selectionRect.minX, y: selectionRect.minY)
        case .bottomRight:
            center = CGPoint(x: selectionRect.maxX, y: selectionRect.minY)
        }

        return CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        ).standardized
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func clamped(_ rect: CGRect) -> CGRect {
        var result = rect
        if result.minX < bounds.minX {
            result.origin.x = bounds.minX
        }
        if result.minY < bounds.minY {
            result.origin.y = bounds.minY
        }
        if result.maxX > bounds.maxX {
            result.origin.x = bounds.maxX - result.width
        }
        if result.maxY > bounds.maxY {
            result.origin.y = bounds.maxY - result.height
        }
        return result.standardized
    }

    @objc private func confirmSelection() {
        guard hasValidSelection else { return }
        onConfirm?(selectionRect.standardized)
    }

    @objc private func cancelSelection() {
        onCancel?()
    }
}
