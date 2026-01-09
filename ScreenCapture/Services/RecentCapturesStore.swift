import Foundation
import AppKit
import CoreGraphics

/// Manages the list of recent captures with thumbnail generation and persistence.
/// Runs on the main actor for UI integration.
@MainActor
final class RecentCapturesStore: ObservableObject {
    // MARK: - Constants

    /// Maximum number of recent captures to store
    private static let maxCaptures = 5

    /// Maximum thumbnail dimension in pixels
    private static let maxThumbnailSize: CGFloat = 128

    /// Maximum thumbnail data size in bytes (10KB)
    private static let maxThumbnailDataSize = 10 * 1024

    /// JPEG quality for thumbnail compression
    private static let thumbnailQuality: CGFloat = 0.7

    // MARK: - Properties

    /// The list of recent captures (newest first)
    @Published private(set) var captures: [RecentCapture] = []

    /// App settings for persistence
    private let settings: AppSettings

    // MARK: - Initialization

    init(settings: AppSettings = .shared) {
        self.settings = settings
        loadCaptures()
    }

    // MARK: - Public API

    /// Adds a new capture to the recent list.
    /// Generates a thumbnail and persists the update.
    /// - Parameters:
    ///   - filePath: The URL where the screenshot was saved
    ///   - image: The captured image for thumbnail generation
    ///   - date: The capture date (defaults to now)
    func add(filePath: URL, image: CGImage, date: Date = Date()) {
        let thumbnailData = generateThumbnail(from: image)

        let capture = RecentCapture(
            filePath: filePath,
            captureDate: date,
            thumbnailData: thumbnailData
        )

        captures.insert(capture, at: 0)

        // Enforce maximum count
        if captures.count > Self.maxCaptures {
            captures = Array(captures.prefix(Self.maxCaptures))
        }

        saveCaptures()
    }

    /// Removes a capture from the recent list.
    /// - Parameter capture: The capture to remove
    func remove(capture: RecentCapture) {
        captures.removeAll { $0.id == capture.id }
        saveCaptures()
    }

    /// Removes the capture at the specified index.
    /// - Parameter index: The index of the capture to remove
    func remove(at index: Int) {
        guard index >= 0 && index < captures.count else { return }
        captures.remove(at: index)
        saveCaptures()
    }

    /// Clears all recent captures.
    func clear() {
        captures.removeAll()
        saveCaptures()
    }

    /// Removes captures whose files no longer exist.
    func pruneInvalidCaptures() {
        captures.removeAll { !$0.fileExists }
        saveCaptures()
    }

    // MARK: - Persistence

    /// Reloads captures from UserDefaults (call before displaying menu)
    func reload() {
        loadCaptures()
    }

    /// Loads captures from UserDefaults via AppSettings
    private func loadCaptures() {
        captures = settings.recentCaptures
        pruneInvalidCaptures()
    }

    /// Saves captures to UserDefaults via AppSettings
    private func saveCaptures() {
        settings.recentCaptures = captures
    }

    // MARK: - Thumbnail Generation

    /// Generates a JPEG thumbnail from a CGImage.
    /// - Parameter image: The source image
    /// - Returns: JPEG data for the thumbnail, or nil if generation fails
    private func generateThumbnail(from image: CGImage) -> Data? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        // Calculate scaled size maintaining aspect ratio
        let scale: CGFloat
        if width > height {
            scale = Self.maxThumbnailSize / width
        } else {
            scale = Self.maxThumbnailSize / height
        }

        // Only scale down, not up
        let finalScale = min(scale, 1.0)
        let newWidth = Int(width * finalScale)
        let newHeight = Int(height * finalScale)

        // Create thumbnail context
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        // Draw scaled image
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        // Get thumbnail image
        guard let thumbnailImage = context.makeImage() else {
            return nil
        }

        // Convert to JPEG data
        let nsImage = NSImage(cgImage: thumbnailImage, size: NSSize(width: newWidth, height: newHeight))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: Self.thumbnailQuality]) else {
            return nil
        }

        // Check size and reduce quality if needed
        if jpegData.count > Self.maxThumbnailDataSize {
            // Try with lower quality
            let lowerQuality: CGFloat = 0.5
            if let reducedData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: lowerQuality]),
               reducedData.count <= Self.maxThumbnailDataSize {
                return reducedData
            }
            // If still too large, return nil
            return nil
        }

        return jpegData
    }
}
