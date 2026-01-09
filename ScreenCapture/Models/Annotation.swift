import Foundation
import CoreGraphics

/// A drawing element placed on a screenshot.
/// Supports rectangle, freehand, arrow, and text annotation types.
enum Annotation: Identifiable, Equatable, Sendable {
    case rectangle(RectangleAnnotation)
    case freehand(FreehandAnnotation)
    case arrow(ArrowAnnotation)
    case text(TextAnnotation)
    case blur(BlurAnnotation)

    /// Unique identifier for this annotation
    var id: UUID {
        switch self {
        case .rectangle(let annotation):
            return annotation.id
        case .freehand(let annotation):
            return annotation.id
        case .arrow(let annotation):
            return annotation.id
        case .text(let annotation):
            return annotation.id
        case .blur(let annotation):
            return annotation.id
        }
    }

    /// The bounding rect of this annotation
    var bounds: CGRect {
        switch self {
        case .rectangle(let annotation):
            return annotation.rect
        case .freehand(let annotation):
            return annotation.bounds
        case .arrow(let annotation):
            return annotation.bounds
        case .text(let annotation):
            return annotation.bounds
        case .blur(let annotation):
            return annotation.rect
        }
    }
}

// MARK: - Rectangle Annotation

/// A rectangle annotation with position, size, and stroke style.
struct RectangleAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Position and size in image coordinates
    var rect: CGRect

    /// Stroke color and line width
    var style: StrokeStyle

    /// Whether the rectangle is filled (solid) or hollow (outline only)
    /// When filled, the rectangle uses the stroke color as fill to hide underlying content
    var isFilled: Bool

    init(id: UUID = UUID(), rect: CGRect, style: StrokeStyle = .default, isFilled: Bool = false) {
        self.id = id
        self.rect = rect
        self.style = style
        self.isFilled = isFilled
    }
}

// MARK: - Freehand Annotation

/// A freehand path annotation with points and stroke style.
struct FreehandAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Path vertices in image coordinates (minimum 2 points)
    var points: [CGPoint]

    /// Stroke color and line width
    var style: StrokeStyle

    init(id: UUID = UUID(), points: [CGPoint], style: StrokeStyle = .default) {
        self.id = id
        self.points = points
        self.style = style
    }

    /// Whether this annotation has enough points to be valid
    var isValid: Bool {
        points.count >= 2
    }

    /// The bounding rectangle of all points
    var bounds: CGRect {
        guard !points.isEmpty else { return .zero }

        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = -CGFloat.infinity
        var maxY = -CGFloat.infinity

        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Arrow Annotation

/// An arrow annotation with start point, end point (arrowhead), and stroke style.
struct ArrowAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Start point of the arrow (tail) in image coordinates
    var startPoint: CGPoint

    /// End point of the arrow (head) in image coordinates
    var endPoint: CGPoint

    /// Stroke color and line width
    var style: StrokeStyle

    init(id: UUID = UUID(), startPoint: CGPoint, endPoint: CGPoint, style: StrokeStyle = .default) {
        self.id = id
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.style = style
    }

    /// Whether this annotation has meaningful length
    var isValid: Bool {
        let dx = endPoint.x - startPoint.x
        let dy = endPoint.y - startPoint.y
        let length = sqrt(dx * dx + dy * dy)
        return length >= 5
    }

    /// The bounding rectangle of the arrow
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        // Add padding for the arrowhead
        let padding: CGFloat = style.lineWidth * 3
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + padding * 2,
            height: maxY - minY + padding * 2
        )
    }
}

// MARK: - Text Annotation

/// A text annotation with position, content, and text style.
struct TextAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Anchor point in image coordinates
    var position: CGPoint

    /// User-entered text content
    var content: String

    /// Font, size, and color
    var style: TextStyle

    init(id: UUID = UUID(), position: CGPoint, content: String, style: TextStyle = .default) {
        self.id = id
        self.position = position
        self.content = content
        self.style = style
    }

    /// Whether this annotation has non-empty content
    var isValid: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Estimated bounds of the text annotation based on font size and content
    var bounds: CGRect {
        // Estimate text size based on font size and character count
        // Average character width is approximately 0.6 × font size for most fonts
        let averageCharWidth = style.fontSize * 0.6
        let estimatedWidth = max(CGFloat(content.count) * averageCharWidth, style.fontSize * 2)
        // Height is approximately 1.2 × font size (line height)
        let estimatedHeight = style.fontSize * 1.3

        return CGRect(
            origin: position,
            size: CGSize(width: estimatedWidth, height: estimatedHeight)
        )
    }
}

// MARK: - Blur Annotation

/// A blur annotation that obscures content along a painted brush stroke.
struct BlurAnnotation: Identifiable, Equatable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Points along the blur brush stroke (in image coordinates)
    var points: [CGPoint]

    /// Blur intensity (sigma value for Gaussian blur)
    var blurRadius: CGFloat

    /// Brush size (diameter of the blur brush)
    var brushSize: CGFloat

    init(id: UUID = UUID(), points: [CGPoint] = [], blurRadius: CGFloat = 15.0, brushSize: CGFloat = 40.0) {
        self.id = id
        self.points = points
        self.blurRadius = blurRadius
        self.brushSize = brushSize
    }

    /// The bounding rect of all points plus brush size
    var rect: CGRect {
        bounds
    }

    /// Computed bounding box of all points
    var bounds: CGRect {
        guard !points.isEmpty else { return .zero }

        let xs = points.map { $0.x }
        let ys = points.map { $0.y }

        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }

        let padding = brushSize / 2
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: maxX - minX + brushSize,
            height: maxY - minY + brushSize
        )
    }

    /// Whether this annotation has meaningful content
    var isValid: Bool {
        points.count >= 2
    }
}

// MARK: - CGPoint Sendable Conformance

extension CGPoint: @retroactive @unchecked Sendable {}

// MARK: - Annotation Type

extension Annotation {
    /// The type of this annotation for display purposes
    var typeName: String {
        switch self {
        case .rectangle:
            return NSLocalizedString("tool.rectangle", comment: "")
        case .freehand:
            return NSLocalizedString("tool.freehand", comment: "")
        case .arrow:
            return NSLocalizedString("tool.arrow", comment: "")
        case .text:
            return NSLocalizedString("tool.text", comment: "")
        case .blur:
            return NSLocalizedString("tool.blur", comment: "")
        }
    }
}
