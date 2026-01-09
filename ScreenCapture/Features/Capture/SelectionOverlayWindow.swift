import AppKit
import CoreGraphics

// MARK: - SelectionOverlayDelegate

/// Delegate protocol for selection overlay events.
@MainActor
protocol SelectionOverlayDelegate: AnyObject {
    /// Called when user completes a selection.
    /// - Parameters:
    ///   - rect: The selected rectangle in screen coordinates
    ///   - display: The display containing the selection
    func selectionOverlay(didSelectRect rect: CGRect, on display: DisplayInfo)

    /// Called when user cancels the selection.
    func selectionOverlayDidCancel()
}

// MARK: - SelectionOverlayWindow

/// NSPanel subclass for displaying the selection overlay.
/// Provides a full-screen transparent overlay with crosshair cursor,
/// dim effect, and selection rectangle drawing.
final class SelectionOverlayWindow: NSPanel {
    // MARK: - Properties

    /// The screen this overlay covers
    let targetScreen: NSScreen

    /// The display info for this screen
    let displayInfo: DisplayInfo

    /// The content view handling drawing and interaction
    private var overlayView: SelectionOverlayView?

    // MARK: - Initialization

    /// Creates a new selection overlay window for the specified screen.
    /// - Parameters:
    ///   - screen: The NSScreen to overlay
    ///   - displayInfo: The DisplayInfo for the screen
    @MainActor
    init(screen: NSScreen, displayInfo: DisplayInfo) {
        self.targetScreen = screen
        self.displayInfo = displayInfo

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configureWindow()
        setupOverlayView()
    }

    // MARK: - Configuration

    @MainActor
    private func configureWindow() {
        // Window properties for full-screen overlay
        level = .screenSaver // Above most windows but below alerts
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        hasShadow = false

        // Don't hide on deactivation
        hidesOnDeactivate = false

        // Behavior
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false

        // Accept mouse events
        acceptsMouseMovedEvents = true
    }

    @MainActor
    private func setupOverlayView() {
        let view = SelectionOverlayView(frame: targetScreen.frame)
        view.autoresizingMask = [.width, .height]
        self.contentView = view
        self.overlayView = view
    }

    // MARK: - Public API

    /// Sets the delegate for selection events
    @MainActor
    func setDelegate(_ delegate: SelectionOverlayDelegate) {
        overlayView?.delegate = delegate
        overlayView?.displayInfo = displayInfo
    }

    /// Updates the current mouse position for crosshair drawing
    @MainActor
    func updateMousePosition(_ point: NSPoint) {
        overlayView?.mousePosition = point
        overlayView?.needsDisplay = true
    }

    /// Updates the selection state (start point and current point)
    @MainActor
    func updateSelection(start: NSPoint?, current: NSPoint?) {
        overlayView?.selectionStart = start
        overlayView?.selectionCurrent = current
        overlayView?.needsDisplay = true
    }

    /// Shows the overlay window
    @MainActor
    func showOverlay() {
        makeKeyAndOrderFront(nil)
    }

    /// Hides and closes the overlay window
    @MainActor
    func hideOverlay() {
        orderOut(nil)
        close()
    }

    // MARK: - NSWindow Overrides

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Make the window accept first responder
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - SelectionOverlayView

/// Custom NSView for drawing the selection overlay.
/// Handles crosshair cursor, dim overlay, and selection rectangle.
final class SelectionOverlayView: NSView {
    // MARK: - Properties

    /// Delegate for selection events
    weak var delegate: SelectionOverlayDelegate?

    /// Display info for coordinate conversion
    var displayInfo: DisplayInfo?

    /// Current mouse position (in window coordinates)
    var mousePosition: NSPoint?

    /// Selection start point (in window coordinates)
    var selectionStart: NSPoint?

    /// Current selection end point (in window coordinates)
    var selectionCurrent: NSPoint?

    /// Whether the user is currently dragging
    private var isDragging = false

    /// Dim overlay color
    private let dimColor = NSColor.black.withAlphaComponent(0.3)

    /// Selection rectangle stroke color
    private let selectionStrokeColor = NSColor.white

    /// Selection rectangle fill color
    private let selectionFillColor = NSColor.white.withAlphaComponent(0.1)

    /// Dimensions label background color
    private let labelBackgroundColor = NSColor.black.withAlphaComponent(0.75)

    /// Dimensions label text color
    private let labelTextColor = NSColor.white

    /// Crosshair line color
    private let crosshairColor = NSColor.white.withAlphaComponent(0.8)

    /// Tracking area for mouse moved events
    private var trackingArea: NSTrackingArea?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        setupTrackingArea()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw dim overlay
        drawDimOverlay(context: context)

        // If we have a selection, cut it out and draw the rectangle
        if let start = selectionStart, let current = selectionCurrent {
            let selectionRect = normalizedRect(from: start, to: current)
            drawSelectionRect(selectionRect, context: context)
            drawDimensionsLabel(for: selectionRect, context: context)
        } else if let mousePos = mousePosition {
            // Draw crosshair when not selecting
            drawCrosshair(at: mousePos, context: context)
        }
    }

    /// Draws the semi-transparent dim overlay
    private func drawDimOverlay(context: CGContext) {
        if let start = selectionStart, let current = selectionCurrent {
            // Draw dim with cutout for selection
            let selectionRect = normalizedRect(from: start, to: current)

            context.saveGState()

            // Create path for the entire view minus the selection
            context.addRect(bounds)
            context.addRect(selectionRect)

            // Use even-odd rule to create the cutout
            context.setFillColor(dimColor.cgColor)
            context.fillPath(using: .evenOdd)

            context.restoreGState()
        } else {
            // Full dim when not selecting
            dimColor.setFill()
            bounds.fill()
        }
    }

    /// Draws the selection rectangle with border
    private func drawSelectionRect(_ rect: CGRect, context: CGContext) {
        // Fill
        selectionFillColor.setFill()
        rect.fill()

        // Stroke
        let strokePath = NSBezierPath(rect: rect)
        strokePath.lineWidth = 1.5
        selectionStrokeColor.setStroke()
        strokePath.stroke()

        // Draw dashed inner border
        context.saveGState()
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        context.setLineWidth(1.0)
        context.addRect(rect.insetBy(dx: 1, dy: 1))
        context.strokePath()
        context.restoreGState()
    }

    /// Draws the crosshair cursor at the specified position
    private func drawCrosshair(at point: NSPoint, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(crosshairColor.cgColor)
        context.setLineWidth(1.0)

        // Horizontal line
        context.move(to: CGPoint(x: 0, y: point.y))
        context.addLine(to: CGPoint(x: bounds.width, y: point.y))

        // Vertical line
        context.move(to: CGPoint(x: point.x, y: 0))
        context.addLine(to: CGPoint(x: point.x, y: bounds.height))

        context.strokePath()
        context.restoreGState()
    }

    /// Draws the dimensions label near the selection rectangle
    private func drawDimensionsLabel(for rect: CGRect, context: CGContext) {
        // Get dimensions in pixels (accounting for scale factor)
        let scaleFactor = displayInfo?.scaleFactor ?? 1.0
        let pixelWidth = Int(rect.width * scaleFactor)
        let pixelHeight = Int(rect.height * scaleFactor)

        let dimensionsText = "\(pixelWidth) × \(pixelHeight)"

        // Text attributes
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: labelTextColor
        ]

        let textSize = (dimensionsText as NSString).size(withAttributes: attributes)
        let labelPadding: CGFloat = 6
        let labelSize = CGSize(
            width: textSize.width + labelPadding * 2,
            height: textSize.height + labelPadding * 2
        )

        // Position the label below and to the right of the selection
        var labelOrigin = CGPoint(
            x: rect.maxX - labelSize.width,
            y: rect.minY - labelSize.height - 8
        )

        // Ensure label stays within screen bounds
        if labelOrigin.x < 0 {
            labelOrigin.x = rect.minX
        }
        if labelOrigin.y < 0 {
            labelOrigin.y = rect.maxY + 8
        }
        if labelOrigin.x + labelSize.width > bounds.width {
            labelOrigin.x = bounds.width - labelSize.width
        }

        let labelRect = CGRect(origin: labelOrigin, size: labelSize)

        // Draw background
        let backgroundPath = NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4)
        labelBackgroundColor.setFill()
        backgroundPath.fill()

        // Draw text
        let textPoint = CGPoint(
            x: labelRect.origin.x + labelPadding,
            y: labelRect.origin.y + labelPadding
        )
        (dimensionsText as NSString).draw(at: textPoint, withAttributes: attributes)
    }

    /// Creates a normalized rectangle from two points (handles any drag direction)
    private func normalizedRect(from start: NSPoint, to end: NSPoint) -> CGRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionStart = point
        selectionCurrent = point
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }

        let point = convert(event.locationInWindow, from: nil)
        selectionCurrent = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging,
              let start = selectionStart,
              let current = selectionCurrent else { return }

        isDragging = false

        // Calculate final selection rectangle
        let selectionRect = normalizedRect(from: start, to: current)

        // Only accept selection if it has meaningful size
        if selectionRect.width >= 10 && selectionRect.height >= 10 {
            // Convert to screen coordinates
            guard let window = self.window,
                  let displayInfo = displayInfo else { return }

            #if DEBUG
            print("=== SELECTION COORDINATE DEBUG ===")
            print("[1] selectionRect (view coords): \(selectionRect)")
            print("[2] window.frame: \(window.frame)")
            print("[3] window.screen?.frame: \(String(describing: window.screen?.frame))")
            #endif

            // The selectionRect is in view coordinates, convert to screen coordinates
            // screenRect is in Cocoa coordinates (Y=0 at bottom of primary screen)
            let screenRect = window.convertToScreen(selectionRect)

            #if DEBUG
            print("[4] screenRect (after convertToScreen): \(screenRect)")
            print("[5] NSScreen.screens.first?.frame: \(String(describing: NSScreen.screens.first?.frame))")
            #endif

            // Get the PRIMARY screen height for coordinate conversion
            // Cocoa screen coords: Y=0 at bottom of PRIMARY screen
            // Quartz/SCK coords: Y=0 at TOP of PRIMARY screen
            // IMPORTANT: Must use primary screen height, not current screen height!
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0

            #if DEBUG
            print("[6] primaryScreenHeight for conversion: \(primaryScreenHeight)")
            #endif

            // Convert from Cocoa coordinates (Y=0 at bottom of primary) to Quartz coordinates (Y=0 at top of primary)
            let quartzY = primaryScreenHeight - screenRect.origin.y - screenRect.height

            #if DEBUG
            print("[7] quartzY (converted): \(quartzY)")
            #endif

            // displayFrame is in Quartz coordinates (from SCDisplay)
            let displayFrame = displayInfo.frame

            #if DEBUG
            print("[8] displayInfo.frame (SCDisplay): \(displayFrame)")
            print("[9] displayInfo.isPrimary: \(displayInfo.isPrimary)")
            #endif

            // Now compute display-relative coordinates (both in Quartz coordinate system)
            let relativeRect = CGRect(
                x: screenRect.origin.x - displayFrame.origin.x,
                y: quartzY - displayFrame.origin.y,
                width: screenRect.width,
                height: screenRect.height
            )

            #if DEBUG
            print("[10] FINAL relativeRect: \(relativeRect)")
            print("[11] Normalized would be: x=\(relativeRect.origin.x / displayFrame.width), y=\(relativeRect.origin.y / displayFrame.height)")
            print("=== END COORDINATE DEBUG ===")
            #endif

            delegate?.selectionOverlay(didSelectRect: relativeRect, on: displayInfo)
        } else {
            // Too small - cancel
            delegate?.selectionOverlayDidCancel()
        }

        // Reset state
        selectionStart = nil
        selectionCurrent = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        mousePosition = point
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) {
        // Change cursor to crosshair
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        // Reset cursor
        NSCursor.arrow.set()
        mousePosition = nil
        needsDisplay = true
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Escape key cancels selection
        if event.keyCode == 53 { // Escape
            isDragging = false
            selectionStart = nil
            selectionCurrent = nil
            delegate?.selectionOverlayDidCancel()
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

// MARK: - SelectionOverlayController

/// Controller for managing selection overlay windows across all displays.
/// Creates and coordinates overlay windows for multi-display spanning selection.
@MainActor
final class SelectionOverlayController {
    // MARK: - Properties

    /// Shared instance
    static let shared = SelectionOverlayController()

    /// All active overlay windows (one per display)
    private var overlayWindows: [SelectionOverlayWindow] = []

    /// Delegate for selection events
    weak var delegate: SelectionOverlayDelegate?

    /// Callback for when selection completes
    var onSelectionComplete: ((CGRect, DisplayInfo) -> Void)?

    /// Callback for when selection is cancelled
    var onSelectionCancel: (() -> Void)?

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Presents selection overlay on all connected displays.
    func presentOverlay() async throws {
        // Get all available displays
        let displays = try await ScreenDetector.shared.availableDisplays()

        // Get matching screens
        let screens = NSScreen.screens

        // Create overlay window for each display
        for display in displays {
            guard let screen = screens.first(where: { screen in
                guard let screenNumber = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID else {
                    return false
                }
                return screenNumber == display.id
            }) else {
                continue
            }

            let overlayWindow = SelectionOverlayWindow(screen: screen, displayInfo: display)
            overlayWindow.setDelegate(self)
            overlayWindows.append(overlayWindow)
        }

        // Show all overlay windows
        for window in overlayWindows {
            window.showOverlay()
        }

        // Make the first window (primary display) key
        if let primaryWindow = overlayWindows.first {
            primaryWindow.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Dismisses all overlay windows.
    func dismissOverlay() {
        for window in overlayWindows {
            window.hideOverlay()
        }
        overlayWindows.removeAll()

        // Reset cursor
        NSCursor.arrow.set()
    }
}

// MARK: - SelectionOverlayController + SelectionOverlayDelegate

extension SelectionOverlayController: SelectionOverlayDelegate {
    func selectionOverlay(didSelectRect rect: CGRect, on display: DisplayInfo) {
        // Dismiss all overlays first
        dismissOverlay()

        // Notify via callback
        onSelectionComplete?(rect, display)
    }

    func selectionOverlayDidCancel() {
        // Dismiss all overlays
        dismissOverlay()

        // Notify via callback
        onSelectionCancel?()
    }
}
