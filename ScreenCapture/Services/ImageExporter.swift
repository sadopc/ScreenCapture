import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers
import CoreImage

/// Service for exporting screenshots to PNG or JPEG files.
/// Uses CGImageDestination for efficient image encoding.
struct ImageExporter: Sendable {
    // MARK: - Constants

    /// Date formatter for generating filenames
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return formatter
    }()

    // MARK: - Public API

    /// Exports an image to a file at the specified URL.
    /// - Parameters:
    ///   - image: The CGImage to export
    ///   - annotations: Annotations to composite onto the image
    ///   - url: The destination file URL
    ///   - format: The export format (PNG or JPEG)
    ///   - quality: JPEG quality (0.0-1.0), ignored for PNG
    /// - Throws: ScreenCaptureError if export fails
    func save(
        _ image: CGImage,
        annotations: [Annotation],
        to url: URL,
        format: ExportFormat,
        quality: Double = 0.9
    ) throws {
        // Composite annotations onto the image if any exist
        let finalImage: CGImage
        if annotations.isEmpty {
            finalImage = image
        } else {
            finalImage = try compositeAnnotations(annotations, onto: image)
        }

        // Verify parent directory exists and is writable
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: directory.path) else {
            throw ScreenCaptureError.invalidSaveLocation(directory)
        }

        // Check for available disk space (rough estimate: 4 bytes per pixel for PNG)
        let estimatedSize = Int64(finalImage.width * finalImage.height * 4)
        do {
            let resourceValues = try directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            if let availableCapacity = resourceValues.volumeAvailableCapacity,
               Int64(availableCapacity) < estimatedSize {
                throw ScreenCaptureError.diskFull
            }
        } catch let error as ScreenCaptureError {
            throw error
        } catch {
            // Ignore disk space check errors, proceed with save
        }

        // Create image destination
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            format.uti.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.exportEncodingFailed(format: format)
        }

        // Configure export options
        var options: [CFString: Any] = [:]
        if format == .jpeg {
            options[kCGImageDestinationLossyCompressionQuality] = quality
        }

        // Add image and finalize
        CGImageDestinationAddImage(destination, finalImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.exportEncodingFailed(format: format)
        }
    }

    /// Generates a filename with the current timestamp.
    /// - Parameter format: The export format to determine file extension
    /// - Returns: A filename like "Screenshot 2024-01-15 at 14.30.45.png"
    func generateFilename(format: ExportFormat) -> String {
        let timestamp = Self.dateFormatter.string(from: Date())
        return "Screenshot \(timestamp).\(format.fileExtension)"
    }

    /// Generates a full file URL for saving.
    /// - Parameters:
    ///   - directory: The save directory
    ///   - format: The export format
    /// - Returns: A URL with a unique filename
    func generateFileURL(in directory: URL, format: ExportFormat) -> URL {
        let filename = generateFilename(format: format)
        var url = directory.appendingPathComponent(filename)

        // Ensure unique filename if file already exists
        var counter = 1
        while FileManager.default.fileExists(atPath: url.path) {
            let baseName = "Screenshot \(Self.dateFormatter.string(from: Date())) (\(counter))"
            url = directory.appendingPathComponent("\(baseName).\(format.fileExtension)")
            counter += 1
        }

        return url
    }

    /// Estimates the file size for an image in the given format.
    /// - Parameters:
    ///   - image: The image to estimate size for
    ///   - format: The export format
    ///   - quality: JPEG quality (affects JPEG estimate)
    /// - Returns: Estimated file size in bytes
    func estimateFileSize(
        for image: CGImage,
        format: ExportFormat,
        quality: Double = 0.9
    ) -> Int {
        let pixelCount = image.width * image.height

        switch format {
        case .png:
            // PNG is lossless, estimate ~4 bytes per pixel (varies with content)
            return pixelCount * 4
        case .jpeg:
            // JPEG size varies with quality and content
            // At quality 0.9, roughly 0.5-1.0 bytes per pixel
            let bytesPerPixel = 0.5 + (0.5 * quality)
            return Int(Double(pixelCount) * bytesPerPixel)
        }
    }

    // MARK: - Annotation Compositing

    /// Composites annotations onto an image.
    /// - Parameters:
    ///   - annotations: The annotations to draw
    ///   - image: The base image
    /// - Returns: A new CGImage with annotations rendered
    /// - Throws: ScreenCaptureError if compositing fails
    private func compositeAnnotations(
        _ annotations: [Annotation],
        onto image: CGImage
    ) throws -> CGImage {
        let width = image.width
        let height = image.height

        // Create drawing context
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw ScreenCaptureError.exportEncodingFailed(format: .png)
        }

        // Draw base image
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Configure for drawing annotations
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw each annotation
        for annotation in annotations {
            renderAnnotation(annotation, in: context, imageHeight: CGFloat(height), baseImage: image)
        }

        // Create final image
        guard let result = context.makeImage() else {
            throw ScreenCaptureError.exportEncodingFailed(format: .png)
        }

        return result
    }

    /// Renders a single annotation into a graphics context.
    /// - Parameters:
    ///   - annotation: The annotation to render
    ///   - context: The graphics context
    ///   - imageHeight: The image height (for coordinate transformation)
    ///   - baseImage: The original image (needed for blur)
    private func renderAnnotation(
        _ annotation: Annotation,
        in context: CGContext,
        imageHeight: CGFloat,
        baseImage: CGImage? = nil
    ) {
        switch annotation {
        case .rectangle(let rect):
            renderRectangle(rect, in: context, imageHeight: imageHeight)
        case .freehand(let freehand):
            renderFreehand(freehand, in: context, imageHeight: imageHeight)
        case .arrow(let arrow):
            renderArrow(arrow, in: context, imageHeight: imageHeight)
        case .text(let text):
            renderText(text, in: context, imageHeight: imageHeight)
        case .blur(let blur):
            if let baseImage = baseImage {
                renderBlur(blur, in: context, imageHeight: imageHeight, baseImage: baseImage)
            }
        }
    }

    /// Renders a rectangle annotation.
    private func renderRectangle(
        _ annotation: RectangleAnnotation,
        in context: CGContext,
        imageHeight: CGFloat
    ) {
        // Transform from SwiftUI coordinates (origin top-left) to CG coordinates (origin bottom-left)
        let rect = CGRect(
            x: annotation.rect.origin.x,
            y: imageHeight - annotation.rect.origin.y - annotation.rect.height,
            width: annotation.rect.width,
            height: annotation.rect.height
        )

        context.setStrokeColor(annotation.style.color.cgColor)
        context.setLineWidth(annotation.style.lineWidth)
        context.stroke(rect)
    }

    /// Renders a freehand annotation.
    private func renderFreehand(
        _ annotation: FreehandAnnotation,
        in context: CGContext,
        imageHeight: CGFloat
    ) {
        guard annotation.points.count >= 2 else { return }

        context.setStrokeColor(annotation.style.color.cgColor)
        context.setLineWidth(annotation.style.lineWidth)

        // Transform points and draw path
        context.beginPath()
        let firstPoint = annotation.points[0]
        context.move(to: CGPoint(x: firstPoint.x, y: imageHeight - firstPoint.y))

        for point in annotation.points.dropFirst() {
            context.addLine(to: CGPoint(x: point.x, y: imageHeight - point.y))
        }

        context.strokePath()
    }

    /// Renders an arrow annotation.
    private func renderArrow(
        _ annotation: ArrowAnnotation,
        in context: CGContext,
        imageHeight: CGFloat
    ) {
        // Transform from SwiftUI coordinates (origin top-left) to CG coordinates (origin bottom-left)
        let start = CGPoint(x: annotation.startPoint.x, y: imageHeight - annotation.startPoint.y)
        let end = CGPoint(x: annotation.endPoint.x, y: imageHeight - annotation.endPoint.y)
        let lineWidth = annotation.style.lineWidth

        context.setStrokeColor(annotation.style.color.cgColor)
        context.setFillColor(annotation.style.color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw the main line
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw the arrowhead
        let arrowHeadLength = max(lineWidth * 4, 12)
        let arrowHeadAngle: CGFloat = .pi / 6

        let dx = end.x - start.x
        let dy = end.y - start.y
        let angle = atan2(dy, dx)

        let arrowPoint1 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: end.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: end.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )

        context.beginPath()
        context.move(to: end)
        context.addLine(to: arrowPoint1)
        context.addLine(to: arrowPoint2)
        context.closePath()
        context.fillPath()
    }

    /// Renders a text annotation.
    private func renderText(
        _ annotation: TextAnnotation,
        in context: CGContext,
        imageHeight: CGFloat
    ) {
        guard !annotation.content.isEmpty else { return }

        // Create attributed string
        let font = NSFont(name: annotation.style.fontName, size: annotation.style.fontSize)
            ?? NSFont.systemFont(ofSize: annotation.style.fontSize)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: annotation.style.color.nsColor
        ]

        let attributedString = NSAttributedString(string: annotation.content, attributes: attributes)

        // Draw text at position (transform Y coordinate)
        let position = CGPoint(
            x: annotation.position.x,
            y: imageHeight - annotation.position.y - annotation.style.fontSize
        )

        // Save context state
        context.saveGState()

        // Create line and draw
        let line = CTLineCreateWithAttributedString(attributedString)
        context.textPosition = position
        CTLineDraw(line, context)

        // Restore context state
        context.restoreGState()
    }

    /// Renders a blur annotation using Gaussian blur with brush-based clipping.
    private func renderBlur(
        _ annotation: BlurAnnotation,
        in context: CGContext,
        imageHeight: CGFloat,
        baseImage: CGImage
    ) {
        guard annotation.points.count >= 2 else { return }

        let imageWidth = CGFloat(baseImage.width)

        // Get bounds of the blur stroke (in SwiftUI coordinates)
        let bounds = annotation.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Clamp to image bounds
        let clampedBounds = CGRect(
            x: max(0, bounds.origin.x),
            y: max(0, bounds.origin.y),
            width: min(bounds.width, imageWidth - max(0, bounds.origin.x)),
            height: min(bounds.height, imageHeight - max(0, bounds.origin.y))
        )

        guard clampedBounds.width > 0, clampedBounds.height > 0 else { return }

        // Convert to CG coordinates (bottom-left origin)
        let cgBounds = CGRect(
            x: clampedBounds.origin.x,
            y: imageHeight - clampedBounds.origin.y - clampedBounds.height,
            width: clampedBounds.width,
            height: clampedBounds.height
        )

        // Crop the region from base image
        guard let croppedImage = baseImage.cropping(to: cgBounds) else { return }

        // Apply Gaussian blur (invert the range so higher values = more blur)
        let ciImage = CIImage(cgImage: croppedImage)
        let effectiveSigma = 35.0 - annotation.blurRadius  // 5→30 (intense), 30→5 (light)
        let blurredCIImage = ciImage.applyingGaussianBlur(sigma: effectiveSigma)

        // Clamp the blurred image back to original bounds (blur expands the extent)
        let clampedBlurred = blurredCIImage.clamped(to: ciImage.extent)
        let ciContext = CIContext()
        guard let blurredCGImage = ciContext.createCGImage(clampedBlurred, from: ciImage.extent) else { return }

        // Create brush stroke path (in CG coordinates)
        let brushPath = CGMutablePath()
        let brushSize = annotation.brushSize

        // Transform points from SwiftUI to CG coordinates
        let cgPoints = annotation.points.map { point in
            CGPoint(x: point.x, y: imageHeight - point.y)
        }

        // Add circles at each point
        for point in cgPoints {
            brushPath.addEllipse(in: CGRect(
                x: point.x - brushSize / 2,
                y: point.y - brushSize / 2,
                width: brushSize,
                height: brushSize
            ))
        }

        // Add stroked line connecting points for continuous coverage
        if cgPoints.count >= 2 {
            let linePath = CGMutablePath()
            linePath.move(to: cgPoints[0])
            for point in cgPoints.dropFirst() {
                linePath.addLine(to: point)
            }
            let strokedLine = linePath.copy(
                strokingWithWidth: brushSize,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            brushPath.addPath(strokedLine)
        }

        // Draw blurred image clipped to brush path
        context.saveGState()
        context.addPath(brushPath)
        context.clip()
        context.draw(blurredCGImage, in: cgBounds)
        context.restoreGState()
    }
}

// MARK: - Shared Instance

extension ImageExporter {
    /// Shared instance for convenience
    static let shared = ImageExporter()
}
