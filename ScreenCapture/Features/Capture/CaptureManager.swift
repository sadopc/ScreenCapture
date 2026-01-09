import Foundation
@preconcurrency import ScreenCaptureKit
import CoreGraphics
import AppKit
import os.signpost

/// Actor responsible for screen capture operations using ScreenCaptureKit.
/// Thread-safe management of capture requests with permission handling.
///
/// ## Memory Usage
/// Peak memory usage is bounded to approximately 2× the captured image size:
/// - 1× for the CGImage buffer from ScreenCaptureKit
/// - 1× for any annotation compositing (temporary, released after save)
///
/// ## Performance Goals
/// - Capture latency: <50ms from trigger to CGImage available
/// - Preview display: <100ms from capture to window visible
/// - Idle CPU: <1% when not capturing
actor CaptureManager {
    // MARK: - Performance Logging

    private static let performanceLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "ScreenCapture",
        category: .pointsOfInterest
    )

    private static let signpostID = OSSignpostID(log: performanceLog)
    // MARK: - Properties

    /// Shared instance for app-wide capture management
    static let shared = CaptureManager()

    /// Screen detector for display enumeration
    private let screenDetector = ScreenDetector.shared

    /// Whether a capture is currently in progress
    private var isCapturing = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Permission Handling

    /// Checks if the app has screen recording permission.
    /// - Returns: True if permission is granted
    var hasPermission: Bool {
        get async {
            await screenDetector.hasPermission
        }
    }

    /// Requests screen recording permission by triggering the system prompt.
    /// Note: ScreenCaptureKit automatically prompts for permission on first capture attempt.
    /// - Returns: True if permission is now granted
    func requestPermission() async -> Bool {
        // Attempt a capture to trigger the permission prompt
        do {
            let displays = try await screenDetector.availableDisplays()
            guard let display = displays.first else { return false }

            // Create a minimal capture configuration just to trigger the prompt
            guard let scContent = try? await SCShareableContent.current,
                  let scDisplay = scContent.displays.first(where: { $0.displayID == display.id }) else {
                return false
            }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 1
            config.height = 1

            // This will trigger the permission prompt if not already granted
            _ = try? await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            return await hasPermission
        } catch {
            return false
        }
    }

    // MARK: - Full Screen Capture

    /// Captures the full screen of the specified display.
    /// - Parameter display: The display to capture
    /// - Returns: Screenshot containing the captured image and metadata
    /// - Throws: ScreenCaptureError if capture fails
    func captureFullScreen(display: DisplayInfo) async throws -> Screenshot {
        // Prevent concurrent captures
        guard !isCapturing else {
            throw ScreenCaptureError.captureError(message: "Capture already in progress")
        }
        isCapturing = true
        defer { isCapturing = false }

        // Check permission
        guard await hasPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        // Invalidate cache to get fresh display list
        await screenDetector.invalidateCache()

        // Get the SCDisplay for this display
        let scContent: SCShareableContent
        do {
            scContent = try await SCShareableContent.current
        } catch {
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        guard let scDisplay = scContent.displays.first(where: { $0.displayID == display.id }) else {
            // Display was disconnected
            throw ScreenCaptureError.displayDisconnected(displayName: display.name)
        }

        // Configure capture
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = createCaptureConfiguration(for: display)

        // Perform capture with signpost for profiling
        os_signpost(.begin, log: Self.performanceLog, name: "FullScreenCapture", signpostID: Self.signpostID)
        let captureStartTime = CFAbsoluteTimeGetCurrent()

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            os_signpost(.end, log: Self.performanceLog, name: "FullScreenCapture", signpostID: Self.signpostID)
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        let captureLatency = (CFAbsoluteTimeGetCurrent() - captureStartTime) * 1000
        os_signpost(.end, log: Self.performanceLog, name: "FullScreenCapture", signpostID: Self.signpostID)

        #if DEBUG
        print("Capture latency: \(String(format: "%.1f", captureLatency))ms")
        #endif

        // Create screenshot with metadata
        let screenshot = Screenshot(
            image: cgImage,
            captureDate: Date(),
            sourceDisplay: display
        )

        return screenshot
    }

    /// Captures the full screen of the primary display.
    /// - Returns: Screenshot containing the captured image and metadata
    /// - Throws: ScreenCaptureError if capture fails
    func captureFullScreen() async throws -> Screenshot {
        let display = try await screenDetector.primaryDisplay()
        return try await captureFullScreen(display: display)
    }

    // MARK: - Region Capture

    /// Captures a specific region of the specified display.
    /// - Parameters:
    ///   - rect: The region to capture in display coordinates
    ///   - display: The display to capture from
    /// - Returns: Screenshot containing the captured region and metadata
    /// - Throws: ScreenCaptureError if capture fails
    func captureRegion(_ rect: CGRect, from display: DisplayInfo) async throws -> Screenshot {
        // Prevent concurrent captures
        guard !isCapturing else {
            throw ScreenCaptureError.captureError(message: "Capture already in progress")
        }
        isCapturing = true
        defer { isCapturing = false }

        // Check permission
        guard await hasPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        // Invalidate cache to get fresh display list
        await screenDetector.invalidateCache()

        // Get the SCDisplay for this display
        let scContent: SCShareableContent
        do {
            scContent = try await SCShareableContent.current
        } catch {
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        guard let scDisplay = scContent.displays.first(where: { $0.displayID == display.id }) else {
            // Display was disconnected
            throw ScreenCaptureError.displayDisconnected(displayName: display.name)
        }

        // Configure capture for the full display at native resolution
        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let config = createCaptureConfiguration(for: display)

        // Calculate the crop region in pixels
        let cropRect = CGRect(
            x: rect.origin.x * display.scaleFactor,
            y: rect.origin.y * display.scaleFactor,
            width: rect.width * display.scaleFactor,
            height: rect.height * display.scaleFactor
        )

        #if DEBUG
        print("=== CAPTURE MANAGER DEBUG ===")
        print("[CAP-1] Input rect (points): \(rect)")
        print("[CAP-2] display.frame (points): \(display.frame)")
        print("[CAP-3] display.scaleFactor: \(display.scaleFactor)")
        print("[CAP-4] cropRect (pixels): \(cropRect)")
        print("=== END CAPTURE MANAGER DEBUG ===")
        #endif

        // Capture full display at native resolution (no sourceRect to avoid scaling)
        os_signpost(.begin, log: Self.performanceLog, name: "RegionCapture", signpostID: Self.signpostID)
        let captureStartTime = CFAbsoluteTimeGetCurrent()

        let fullImage: CGImage
        do {
            fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
        } catch {
            os_signpost(.end, log: Self.performanceLog, name: "RegionCapture", signpostID: Self.signpostID)
            throw ScreenCaptureError.captureFailure(underlying: error)
        }

        // Crop to the selected region - this preserves pixel-perfect quality
        guard let cgImage = fullImage.cropping(to: cropRect) else {
            os_signpost(.end, log: Self.performanceLog, name: "RegionCapture", signpostID: Self.signpostID)
            throw ScreenCaptureError.captureError(message: "Failed to crop region")
        }

        let captureLatency = (CFAbsoluteTimeGetCurrent() - captureStartTime) * 1000
        os_signpost(.end, log: Self.performanceLog, name: "RegionCapture", signpostID: Self.signpostID)

        #if DEBUG
        print("Region capture latency: \(String(format: "%.1f", captureLatency))ms")
        print("[CAP-5] Full image size: \(fullImage.width)x\(fullImage.height)")
        print("[CAP-6] Cropped image size: \(cgImage.width)x\(cgImage.height)")
        #endif

        // Create screenshot with metadata
        let screenshot = Screenshot(
            image: cgImage,
            captureDate: Date(),
            sourceDisplay: display
        )

        return screenshot
    }

    // MARK: - Display Enumeration

    /// Returns all available displays for capture.
    /// - Returns: Array of DisplayInfo for all connected displays
    /// - Throws: ScreenCaptureError if enumeration fails
    func availableDisplays() async throws -> [DisplayInfo] {
        try await screenDetector.availableDisplays()
    }

    /// Returns the primary display.
    /// - Returns: DisplayInfo for the main display
    /// - Throws: ScreenCaptureError if no primary display found
    func primaryDisplay() async throws -> DisplayInfo {
        try await screenDetector.primaryDisplay()
    }

    // MARK: - Private Methods

    /// Creates a capture configuration optimized for the given display.
    /// - Parameter display: The display to configure for
    /// - Returns: SCStreamConfiguration with appropriate settings
    private func createCaptureConfiguration(for display: DisplayInfo) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()

        // Set dimensions to match display's pixel resolution
        config.width = Int(display.frame.width * display.scaleFactor)
        config.height = Int(display.frame.height * display.scaleFactor)

        // CRITICAL: Don't scale - capture at native pixel resolution
        config.scalesToFit = false

        // High quality settings for screenshots
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // Single frame
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false // Typically hide cursor in screenshots

        // Color settings for accurate reproduction
        config.colorSpaceName = CGColorSpace.sRGB

        // Use best capture resolution on macOS 14+
        if #available(macOS 14.0, *) {
            config.captureResolution = .best
        }

        return config
    }
}
