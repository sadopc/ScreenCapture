import AppKit
import ScreenCaptureKit

// MARK: - Window Info

/// Window information for selection
struct SelectableWindow {
    let windowID: CGWindowID
    let frame: CGRect
    let name: String
}

// MARK: - WindowSelectorController

/// Manages window selection using a visual overlay.
@MainActor
final class WindowSelectorController: NSObject {
    // MARK: - Singleton

    static let shared = WindowSelectorController()

    // MARK: - Properties

    /// Callback for window selection
    var onWindowSelected: ((CGWindowID) -> Void)?

    /// Callback for cancellation
    var onCancel: (() -> Void)?

    /// Overlay panel
    private var overlayPanel: NSPanel?

    /// Cached windows
    private var windows: [SelectableWindow] = []

    /// Currently highlighted window
    private var highlightedWindow: SelectableWindow?

    /// Tracking area for mouse movement
    private var trackingArea: NSTrackingArea?

    /// Main screen height for coordinate conversion
    private var mainScreenHeight: CGFloat = 0

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// Presents the window selector.
    func presentSelector() async throws {
        mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0

        // Get windows before showing overlay
        windows = getWindowList()

        guard !windows.isEmpty else {
            throw ScreenCaptureError.captureError(message: "No windows available")
        }

        #if DEBUG
        print("=== Window Selector ===")
        print("Found \(windows.count) windows")
        #endif

        // Create and show overlay
        showOverlay()
    }

    /// Dismisses the selector.
    func dismissSelector() {
        // Remove key monitor
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        // Close all overlay panels
        for panel in overlayPanels {
            panel.orderOut(nil)
            panel.close()
        }
        overlayPanels = []
        overlayPanel = nil
        windows = []
        highlightedWindow = nil
    }

    // MARK: - Window List

    private func getWindowList() -> [SelectableWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [SelectableWindow] = []

        for info in infoList {
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else { continue }

            // Skip small windows
            guard width >= 100 && height >= 100 else { continue }

            // Skip our own app
            if let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == myPID { continue }

            // Only layer 0 (normal windows)
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let windowName = info[kCGWindowName as String] as? String ?? ""
            let name = windowName.isEmpty ? ownerName : "\(ownerName) - \(windowName)"

            result.append(SelectableWindow(
                windowID: windowID,
                frame: CGRect(x: x, y: y, width: width, height: height),
                name: name
            ))
        }

        return result
    }

    /// Overlay panels for all screens
    private var overlayPanels: [NSPanel] = []

    /// Key monitor
    private var keyMonitor: Any?

    // MARK: - Overlay

    private func showOverlay() {
        // Create overlay for ALL screens
        for screen in NSScreen.screens {
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.3)
            panel.hasShadow = false
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // Create content view with local coordinates
            let contentView = OverlayContentView(frame: NSRect(origin: .zero, size: screen.frame.size))
            contentView.controller = self
            contentView.screenFrame = screen.frame  // Store screen frame for coordinate conversion
            contentView.wantsLayer = true
            panel.contentView = contentView

            // Add tracking area for mouse movement
            let trackingArea = NSTrackingArea(
                rect: contentView.bounds,
                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                owner: contentView,
                userInfo: nil
            )
            contentView.addTrackingArea(trackingArea)

            overlayPanels.append(panel)
            panel.makeKeyAndOrderFront(nil)
        }

        // Use first panel as main overlay
        overlayPanel = overlayPanels.first

        // Monitor for ESC key
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.handleCancel()
                return nil
            }
            return event
        }
    }

    // MARK: - Coordinate Conversion

    func windowAtPoint(_ cocoaPoint: CGPoint) -> SelectableWindow? {
        // Convert Cocoa to Quartz coordinates
        let quartzPoint = CGPoint(x: cocoaPoint.x, y: mainScreenHeight - cocoaPoint.y)

        return windows.first { $0.frame.contains(quartzPoint) }
    }

    func quartzToCocoaFrame(_ quartzFrame: CGRect) -> CGRect {
        return CGRect(
            x: quartzFrame.origin.x,
            y: mainScreenHeight - quartzFrame.origin.y - quartzFrame.height,
            width: quartzFrame.width,
            height: quartzFrame.height
        )
    }

    // MARK: - Event Handling

    func handleMouseMoved(at point: CGPoint) {
        highlightedWindow = windowAtPoint(point)

        // Update ALL overlay views
        for panel in overlayPanels {
            guard let view = panel.contentView as? OverlayContentView else { continue }

            if let window = highlightedWindow {
                let cocoaFrame = quartzToCocoaFrame(window.frame)
                // Convert to view-local coordinates
                let localFrame = CGRect(
                    x: cocoaFrame.origin.x - view.screenFrame.origin.x,
                    y: cocoaFrame.origin.y - view.screenFrame.origin.y,
                    width: cocoaFrame.width,
                    height: cocoaFrame.height
                )
                // Only show if it intersects this screen
                if localFrame.intersects(view.bounds) {
                    view.highlightFrame = localFrame
                    view.highlightName = window.name
                } else {
                    view.highlightFrame = nil
                    view.highlightName = nil
                }
            } else {
                view.highlightFrame = nil
                view.highlightName = nil
            }
            view.needsDisplay = true
        }
    }

    func handleClick() {
        guard let window = highlightedWindow else { return }

        #if DEBUG
        print("Selected window: \(window.name) ID: \(window.windowID)")
        #endif

        let windowID = window.windowID
        dismissSelector()
        onWindowSelected?(windowID)
    }

    func handleCancel() {
        #if DEBUG
        print("Selection cancelled")
        #endif

        dismissSelector()
        onCancel?()
    }
}

// MARK: - Overlay Content View

private class OverlayContentView: NSView {
    weak var controller: WindowSelectorController?
    var highlightFrame: CGRect?
    var highlightName: String?
    var screenFrame: CGRect = .zero  // The screen this view is on

    override func draw(_ dirtyRect: NSRect) {
        // Background is already set by panel backgroundColor

        guard let highlightFrame = highlightFrame else {
            // Draw instructions only
            drawInstructions()
            return
        }

        // Draw "hole" for highlighted window
        NSColor.clear.setFill()
        let path = NSBezierPath(rect: highlightFrame)
        path.fill()

        // Draw blue border
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: highlightFrame.insetBy(dx: -3, dy: -3))
        borderPath.lineWidth = 6
        borderPath.stroke()

        // Draw label
        if let name = highlightName {
            drawLabel(name, below: highlightFrame)
        }

        drawInstructions()
    }

    private func drawLabel(_ text: String, below rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = rect.midX - size.width / 2
        let y = rect.minY - size.height - 20

        // Background
        let bgRect = CGRect(x: x - 12, y: y - 4, width: size.width + 24, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 6, yRadius: 6).fill()

        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    private func drawInstructions() {
        let text = "Click on a window to capture. Press ESC to cancel."
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = bounds.midX - size.width / 2
        let y = bounds.maxY - 80

        let bgRect = CGRect(x: x - 20, y: y - 6, width: size.width + 40, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 10, yRadius: 10).fill()

        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        controller?.handleMouseMoved(at: point)
    }

    override func mouseDown(with event: NSEvent) {
        controller?.handleClick()
    }

    override var acceptsFirstResponder: Bool { true }
}
