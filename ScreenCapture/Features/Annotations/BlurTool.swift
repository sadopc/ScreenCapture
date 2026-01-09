import Foundation
import CoreGraphics

/// Tool for drawing blur annotations using a brush.
/// User paints over areas to blur them, similar to freehand drawing.
@MainActor
struct BlurTool: AnnotationTool {
    // MARK: - Properties

    let toolType: AnnotationToolType = .blur

    var strokeStyle: StrokeStyle = .default

    var textStyle: TextStyle = .default

    /// Blur intensity (sigma value for Gaussian blur) - captured at drawing start
    private var capturedBlurRadius: CGFloat = 15.0

    /// Brush size (diameter of the blur brush) - captured at drawing start
    private var capturedBrushSize: CGFloat = 40.0

    private var drawingState = DrawingState()

    /// Minimum distance between recorded points (for performance)
    private let minimumPointDistance: CGFloat = 3.0

    // MARK: - Public setters for configuration

    var blurRadius: CGFloat {
        get { capturedBlurRadius }
        set { capturedBlurRadius = newValue }
    }

    var brushSize: CGFloat {
        get { capturedBrushSize }
        set { capturedBrushSize = newValue }
    }

    // MARK: - AnnotationTool Conformance

    var isActive: Bool {
        drawingState.isDrawing
    }

    var currentAnnotation: Annotation? {
        guard isActive else { return nil }
        let allPoints = [drawingState.startPoint] + drawingState.points
        guard allPoints.count >= 2 else { return nil }
        return .blur(BlurAnnotation(
            points: allPoints,
            blurRadius: capturedBlurRadius,
            brushSize: capturedBrushSize
        ))
    }

    mutating func beginDrawing(at point: CGPoint) {
        drawingState = DrawingState(startPoint: point)
        drawingState.isDrawing = true
    }

    mutating func continueDrawing(to point: CGPoint) {
        guard isActive else { return }

        // Only add point if it's far enough from the last point
        if let lastPoint = drawingState.points.last {
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance >= minimumPointDistance {
                drawingState.points.append(point)
            }
        } else {
            // First continuation point
            let dx = point.x - drawingState.startPoint.x
            let dy = point.y - drawingState.startPoint.y
            let distance = sqrt(dx * dx + dy * dy)

            if distance >= minimumPointDistance {
                drawingState.points.append(point)
            }
        }
    }

    mutating func endDrawing(at point: CGPoint) -> Annotation? {
        guard isActive else { return nil }

        // Add final point
        continueDrawing(to: point)

        // Build the final points array
        let allPoints = [drawingState.startPoint] + drawingState.points
        drawingState.reset()

        // Need at least 2 points for a valid blur stroke
        guard allPoints.count >= 2 else { return nil }

        return .blur(BlurAnnotation(
            points: allPoints,
            blurRadius: blurRadius,
            brushSize: brushSize
        ))
    }

    mutating func cancelDrawing() {
        drawingState.reset()
    }
}
