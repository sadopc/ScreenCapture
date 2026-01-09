import Foundation
import ScreenCaptureKit
import AppKit

/// Sendable window info for cross-actor transfer
struct WindowInfo: Sendable {
    let id: CGWindowID
    let title: String
    let appName: String
    let frame: CGRect
}

/// Actor responsible for capturing specific windows using ScreenCaptureKit.
/// Provides window enumeration and capture functionality with proper coordinate handling.
actor WindowCaptureService {
    // MARK: - Singleton

    /// Shared instance for app-wide window capture
    static let shared = WindowCaptureService()

    // MARK: - Properties

    /// Cached windows from last enumeration
    private var cachedWindows: [SCWindow] = []

    /// Last time windows were enumerated
    private var lastEnumerationTime: Date?

    /// Cache validity duration (100ms for responsive UI)
    private let cacheValidityDuration: TimeInterval = 0.1

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Returns all visible, capturable windows.
    /// Filters out system windows, our own app, and windows that are too small.
    /// - Returns: Array of SCWindow for all capturable windows
    /// - Throws: ScreenCaptureError if enumeration fails
    func getWindows() async throws -> [SCWindow] {
        // Check cache validity
        if let lastTime = lastEnumerationTime,
           Date().timeIntervalSince(lastTime) < cacheValidityDuration,
           !cachedWindows.isEmpty {
            return cachedWindows
        }

        // Enumerate windows using ScreenCaptureKit
        // excludingDesktopWindows: true = exclude desktop/wallpaper windows
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        // Filter windows
        let myBundleID = Bundle.main.bundleIdentifier
        let filteredWindows = content.windows.filter { window in
            // Must have an owning application
            guard let app = window.owningApplication else {
                return false
            }

            // Exclude our own app
            if app.bundleIdentifier == myBundleID {
                return false
            }

            // Exclude windows that are too small (likely UI elements)
            if window.frame.width < 50 || window.frame.height < 50 {
                return false
            }

            // Exclude Finder desktop windows (they cover the whole screen)
            if app.bundleIdentifier == "com.apple.finder" && window.title == nil {
                return false
            }

            // Exclude windows below layer 0 (desktop level)
            // Note: Normal windows are at layer 0, so we only exclude negative layers
            if window.windowLayer < 0 {
                return false
            }

            return true
        }

        // Sort by window layer (frontmost first) - lower windowLayer = more front
        let sortedWindows = filteredWindows.sorted { $0.windowLayer < $1.windowLayer }

        // Update cache
        cachedWindows = sortedWindows
        lastEnumerationTime = Date()

        return sortedWindows
    }

    /// Returns window info as Sendable data for UI display.
    /// - Returns: Array of WindowInfo for all capturable windows
    /// - Throws: ScreenCaptureError if enumeration fails
    func getWindowInfoList() async throws -> [WindowInfo] {
        let windows = try await getWindows()
        return windows.map { window in
            WindowInfo(
                id: window.windowID,
                title: window.title ?? "",
                appName: window.owningApplication?.applicationName ?? "Unknown",
                frame: window.frame
            )
        }
    }

    /// Finds the topmost window at the given screen point.
    /// - Parameter point: Point in screen coordinates (Quartz: Y=0 at top)
    /// - Returns: Window info tuple (windowID, frame, displayName) if found
    func windowAtPoint(_ point: CGPoint) async throws -> (windowID: CGWindowID, frame: CGRect, displayName: String)? {
        let windows = try await getWindows()

        // SCWindow.frame is in screen coordinates with Y=0 at top
        // Find the first (topmost) window containing this point
        if let window = windows.first(where: { $0.frame.contains(point) }) {
            return (window.windowID, window.frame, window.displayName)
        }
        return nil
    }

    /// Captures the window with the given ID.
    /// - Parameters:
    ///   - windowID: The CGWindowID to capture
    ///   - includeShadow: Whether to include the window shadow in the capture
    /// - Returns: Screenshot containing the captured window image
    /// - Throws: ScreenCaptureError if capture fails
    func captureWindowByID(_ windowID: CGWindowID, includeShadow: Bool = false) async throws -> Screenshot {
        // Invalidate cache to get fresh window list
        invalidateCache()
        let windows = try await getWindows()

        guard let window = windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.captureError(message: "Window not found (ID: \(windowID))")
        }

        if includeShadow {
            return try await captureWindowWithShadow(windowID: windowID, window: window)
        } else {
            return try await captureWindow(window)
        }
    }

    /// Captures a window with its shadow by capturing a larger region
    /// - Parameters:
    ///   - windowID: The CGWindowID to capture
    ///   - window: The SCWindow for display info
    /// - Returns: Screenshot containing the captured window with shadow
    private func captureWindowWithShadow(windowID: CGWindowID, window: SCWindow) async throws -> Screenshot {
        // Shadow is typically about 20-30 pixels around the window
        // We'll capture a region larger than the window to include the shadow
        let shadowPadding: CGFloat = 30

        // Get the display containing this window
        let display = try await findDisplayForWindow(window)

        // Calculate the expanded rect with shadow padding
        let expandedRect = CGRect(
            x: max(0, window.frame.origin.x - shadowPadding - display.frame.origin.x),
            y: max(0, window.frame.origin.y - shadowPadding - display.frame.origin.y),
            width: window.frame.width + shadowPadding * 2,
            height: window.frame.height + shadowPadding * 2
        )

        // Get the SCDisplay for this display
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scDisplay = content.displays.first(where: { $0.displayID == display.id }) else {
            throw ScreenCaptureError.captureError(message: "Display not found for window capture")
        }

        // Create filter to capture just this window on the display
        // We include the window in the filter to get its shadow
        let filter = SCContentFilter(display: scDisplay, including: [window])

        // Configure capture
        let config = SCStreamConfiguration()
        let scaleFactor = await MainActor.run {
            NSScreen.screens.first(where: {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.id
            })?.backingScaleFactor ?? 2.0
        }

        config.width = Int(expandedRect.width * scaleFactor)
        config.height = Int(expandedRect.height * scaleFactor)
        config.sourceRect = expandedRect
        config.scalesToFit = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        if #available(macOS 14.0, *) {
            config.captureResolution = .best
        }

        // Capture
        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        return Screenshot(
            image: cgImage,
            captureDate: Date(),
            sourceDisplay: display
        )
    }

    /// Captures the specified window.
    /// - Parameter window: The SCWindow to capture
    /// - Returns: Screenshot containing the captured window image
    /// - Throws: ScreenCaptureError if capture fails
    func captureWindow(_ window: SCWindow) async throws -> Screenshot {
        // Create content filter for just this window
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Configure capture for retina resolution
        let config = SCStreamConfiguration()

        // Get the actual scale factor from the window's screen
        // Extract window frame values before MainActor closure to avoid data race
        let windowFrame = window.frame
        let scaleFactor = await MainActor.run {
            // Find the screen containing this window
            let windowCenter = CGPoint(
                x: windowFrame.midX,
                y: windowFrame.midY
            )

            // Convert Quartz Y to Cocoa Y for NSScreen lookup
            let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
            let cocoaY = primaryScreenHeight - windowCenter.y

            let cocoaPoint = CGPoint(x: windowCenter.x, y: cocoaY)

            let matchingScreen = NSScreen.screens.first { screen in
                screen.frame.contains(cocoaPoint)
            }

            return matchingScreen?.backingScaleFactor ?? 2.0
        }

        config.width = Int(window.frame.width * scaleFactor)
        config.height = Int(window.frame.height * scaleFactor)
        config.scalesToFit = false  // Don't scale - capture at native resolution
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB

        // Try to capture at highest resolution
        if #available(macOS 14.0, *) {
            config.captureResolution = .best
        }

        // Capture the window
        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        // Create display info for the window's location
        // Get the display containing this window
        let display = try await findDisplayForWindow(window)

        // Create screenshot
        let screenshot = Screenshot(
            image: cgImage,
            captureDate: Date(),
            sourceDisplay: display
        )

        return screenshot
    }

    /// Invalidates the window cache, forcing a fresh enumeration on next call.
    func invalidateCache() {
        cachedWindows = []
        lastEnumerationTime = nil
    }

    // MARK: - Private Helpers

    /// Finds the display that contains the given window.
    private func findDisplayForWindow(_ window: SCWindow) async throws -> DisplayInfo {
        let displays = try await ScreenDetector.shared.availableDisplays()

        // Find display containing window center
        let windowCenter = CGPoint(
            x: window.frame.midX,
            y: window.frame.midY
        )

        if let display = displays.first(where: { $0.frame.contains(windowCenter) }) {
            return display
        }

        // Fallback to primary display
        if let primary = displays.first {
            return primary
        }

        throw ScreenCaptureError.captureError(message: "No display found for window")
    }
}

// MARK: - Window Info Extension

extension SCWindow {
    /// Human-readable display name for this window
    var displayName: String {
        if let title = title, !title.isEmpty {
            if let app = owningApplication, !app.applicationName.isEmpty {
                return "\(app.applicationName) - \(title)"
            }
            return title
        }

        if let app = owningApplication, !app.applicationName.isEmpty {
            return app.applicationName
        }

        return "Unknown Window"
    }

    /// Just the application name
    var appName: String {
        owningApplication?.applicationName ?? "Unknown"
    }
}
