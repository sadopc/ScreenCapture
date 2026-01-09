import SwiftUI
import AppKit
import CoreImage

/// SwiftUI Canvas view for drawing and displaying annotations.
/// Renders existing annotations and in-progress drawing.
struct AnnotationCanvas: View {
    // MARK: - Properties

    /// The annotations to display
    let annotations: [Annotation]

    /// The current in-progress annotation (being drawn)
    let currentAnnotation: Annotation?

    /// The size of the canvas (matches image size)
    let canvasSize: CGSize

    /// Scale factor for rendering (canvas to view)
    let scale: CGFloat

    /// Index of the selected annotation (nil = none selected)
    var selectedIndex: Int?

    /// The original image (needed for blur rendering)
    var originalImage: CGImage?

    /// Cached CIContext for blur rendering
    private static let ciContext = CIContext()

    // MARK: - Body

    var body: some View {
        Canvas { context, size in
            // Draw all completed annotations
            for (index, annotation) in annotations.enumerated() {
                drawAnnotation(annotation, in: &context, size: size)

                // Draw selection indicator if this annotation is selected
                if index == selectedIndex {
                    drawSelectionIndicator(for: annotation, in: &context, size: size)
                }
            }

            // Draw current in-progress annotation
            if let current = currentAnnotation {
                drawAnnotation(current, in: &context, size: size)
            }
        }
        .allowsHitTesting(false) // Pass through mouse events
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    /// Generates an accessibility description of the annotations
    private var accessibilityDescription: String {
        let totalCount = annotations.count + (currentAnnotation != nil ? 1 : 0)
        if totalCount == 0 {
            return "No annotations"
        }

        let rectangleCount = annotations.filter {
            if case .rectangle = $0 { return true }
            return false
        }.count

        let freehandCount = annotations.filter {
            if case .freehand = $0 { return true }
            return false
        }.count

        let textCount = annotations.filter {
            if case .text = $0 { return true }
            return false
        }.count

        let blurCount = annotations.filter {
            if case .blur = $0 { return true }
            return false
        }.count

        var parts: [String] = []
        if rectangleCount > 0 {
            parts.append("\(rectangleCount) rectangle\(rectangleCount == 1 ? "" : "s")")
        }
        if freehandCount > 0 {
            parts.append("\(freehandCount) drawing\(freehandCount == 1 ? "" : "s")")
        }
        if textCount > 0 {
            parts.append("\(textCount) text\(textCount == 1 ? "" : "s")")
        }
        if blurCount > 0 {
            parts.append("\(blurCount) blur\(blurCount == 1 ? "" : "s")")
        }

        return "Annotations: \(parts.joined(separator: ", "))"
    }

    // MARK: - Drawing Methods

    /// Draws an annotation in the graphics context
    private func drawAnnotation(
        _ annotation: Annotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        switch annotation {
        case .rectangle(let rect):
            drawRectangle(rect, in: &context, size: size)
        case .freehand(let freehand):
            drawFreehand(freehand, in: &context, size: size)
        case .arrow(let arrow):
            drawArrow(arrow, in: &context, size: size)
        case .text(let text):
            drawText(text, in: &context, size: size)
        case .blur(let blur):
            drawBlur(blur, in: &context, size: size)
        }
    }

    /// Draws a rectangle annotation
    private func drawRectangle(
        _ annotation: RectangleAnnotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let scaledRect = scaleRect(annotation.rect)
        let path = Path(scaledRect)

        if annotation.isFilled {
            // Filled rectangle - solid color to hide underlying content
            context.fill(
                path,
                with: .color(annotation.style.color.color)
            )
        } else {
            // Hollow rectangle - outline only
            context.stroke(
                path,
                with: .color(annotation.style.color.color),
                lineWidth: annotation.style.lineWidth * scale
            )
        }
    }

    /// Draws a freehand annotation
    private func drawFreehand(
        _ annotation: FreehandAnnotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard annotation.points.count >= 2 else { return }

        var path = Path()
        let scaledPoints = annotation.points.map { scalePoint($0) }

        path.move(to: scaledPoints[0])
        for point in scaledPoints.dropFirst() {
            path.addLine(to: point)
        }

        context.stroke(
            path,
            with: .color(annotation.style.color.color),
            style: SwiftUI.StrokeStyle(
                lineWidth: annotation.style.lineWidth * scale,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    /// Draws an arrow annotation
    private func drawArrow(
        _ annotation: ArrowAnnotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let scaledStart = scalePoint(annotation.startPoint)
        let scaledEnd = scalePoint(annotation.endPoint)
        let lineWidth = annotation.style.lineWidth * scale
        let color = annotation.style.color.color

        // Draw the main line
        var linePath = Path()
        linePath.move(to: scaledStart)
        linePath.addLine(to: scaledEnd)

        context.stroke(
            linePath,
            with: .color(color),
            style: SwiftUI.StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )

        // Draw the arrowhead
        let arrowHeadLength = max(lineWidth * 4, 12 * scale)
        let arrowHeadAngle: CGFloat = .pi / 6 // 30 degrees

        // Calculate the angle of the line
        let dx = scaledEnd.x - scaledStart.x
        let dy = scaledEnd.y - scaledStart.y
        let angle = atan2(dy, dx)

        // Calculate arrowhead points
        let arrowPoint1 = CGPoint(
            x: scaledEnd.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: scaledEnd.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )
        let arrowPoint2 = CGPoint(
            x: scaledEnd.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: scaledEnd.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )

        // Draw filled arrowhead
        var arrowHeadPath = Path()
        arrowHeadPath.move(to: scaledEnd)
        arrowHeadPath.addLine(to: arrowPoint1)
        arrowHeadPath.addLine(to: arrowPoint2)
        arrowHeadPath.closeSubpath()

        context.fill(arrowHeadPath, with: .color(color))
    }

    /// Draws a text annotation
    private func drawText(
        _ annotation: TextAnnotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard !annotation.content.isEmpty else { return }

        let scaledPoint = scalePoint(annotation.position)
        let scaledFontSize = annotation.style.fontSize * scale

        let text = Text(annotation.content)
            .font(annotation.style.fontName == ".AppleSystemUIFont"
                  ? .system(size: scaledFontSize)
                  : .custom(annotation.style.fontName, size: scaledFontSize))
            .foregroundColor(annotation.style.color.color)

        context.draw(
            context.resolve(text),
            at: scaledPoint,
            anchor: .topLeading
        )
    }

    /// Draws a blur annotation with brush-based blur effect
    private func drawBlur(
        _ annotation: BlurAnnotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard annotation.points.count >= 2 else { return }

        guard let originalImage = originalImage else {
            drawBlurPlaceholder(annotation, in: &context)
            return
        }

        let imageWidth = CGFloat(originalImage.width)
        let imageHeight = CGFloat(originalImage.height)

        // Get bounds of the blur stroke
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

        // Crop the region
        guard let croppedImage = originalImage.cropping(to: cgBounds) else { return }

        // Apply Gaussian blur (invert the range so higher values = more blur)
        let ciImage = CIImage(cgImage: croppedImage)
        let effectiveSigma = 35.0 - annotation.blurRadius  // 5→30 (intense), 30→5 (light)
        let blurredCIImage = ciImage.applyingGaussianBlur(sigma: effectiveSigma)

        // Clamp the blurred image back to original bounds (blur expands the extent)
        let clampedBlurred = blurredCIImage.clamped(to: ciImage.extent)
        guard let blurredCGImage = Self.ciContext.createCGImage(clampedBlurred, from: ciImage.extent) else {
            drawBlurPlaceholder(annotation, in: &context)
            return
        }

        // Create the brush stroke path in view coordinates
        var brushPath = Path()
        let scaledPoints = annotation.points.map { scalePoint($0) }
        let scaledBrushSize = annotation.brushSize * scale

        for point in scaledPoints {
            brushPath.addEllipse(in: CGRect(
                x: point.x - scaledBrushSize / 2,
                y: point.y - scaledBrushSize / 2,
                width: scaledBrushSize,
                height: scaledBrushSize
            ))
        }

        // Also connect points with thick line for continuous coverage
        if scaledPoints.count >= 2 {
            var linePath = Path()
            linePath.move(to: scaledPoints[0])
            for point in scaledPoints.dropFirst() {
                linePath.addLine(to: point)
            }
            let strokedLine = linePath.strokedPath(SwiftUI.StrokeStyle(
                lineWidth: scaledBrushSize,
                lineCap: .round,
                lineJoin: .round
            ))
            brushPath.addPath(strokedLine)
        }

        // Draw the blurred image clipped to the brush path
        let scaledBounds = scaleRect(clampedBounds)
        let blurImage = Image(decorative: blurredCGImage, scale: 1.0)

        // Use drawLayer to isolate the clipping operation
        context.drawLayer { layerContext in
            var ctx = layerContext
            ctx.clip(to: brushPath)
            ctx.draw(blurImage, in: scaledBounds)
        }
    }

    /// Fallback placeholder when blur can't be rendered
    private func drawBlurPlaceholder(
        _ annotation: BlurAnnotation,
        in context: inout GraphicsContext
    ) {
        guard annotation.points.count >= 2 else { return }

        // Draw the brush stroke path as a visual indicator
        var brushPath = Path()
        let scaledPoints = annotation.points.map { scalePoint($0) }
        let scaledBrushSize = annotation.brushSize * scale

        if scaledPoints.count >= 2 {
            brushPath.move(to: scaledPoints[0])
            for point in scaledPoints.dropFirst() {
                brushPath.addLine(to: point)
            }
        }

        context.stroke(
            brushPath,
            with: .color(.white.opacity(0.6)),
            style: SwiftUI.StrokeStyle(lineWidth: scaledBrushSize, lineCap: .round, lineJoin: .round)
        )
    }

    /// Draws a selection indicator around an annotation
    private func drawSelectionIndicator(
        for annotation: Annotation,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let bounds = annotation.bounds
        let scaledBounds = scaleRect(bounds)

        // Add padding around the bounds
        let padding: CGFloat = 4 * scale
        let selectionRect = scaledBounds.insetBy(dx: -padding, dy: -padding)

        // Draw selection border (dashed blue line)
        let borderPath = Path(roundedRect: selectionRect, cornerRadius: 3 * scale)
        context.stroke(
            borderPath,
            with: .color(.accentColor),
            style: SwiftUI.StrokeStyle(
                lineWidth: 2,
                lineCap: .round,
                dash: [6, 4]
            )
        )

        // Draw corner handles
        let handleSize: CGFloat = 8
        let handlePositions = [
            CGPoint(x: selectionRect.minX, y: selectionRect.minY), // Top-left
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY), // Top-right
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY), // Bottom-left
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY)  // Bottom-right
        ]

        for position in handlePositions {
            let handleRect = CGRect(
                x: position.x - handleSize / 2,
                y: position.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            let handlePath = Path(ellipseIn: handleRect)

            // White fill with blue border
            context.fill(handlePath, with: .color(.white))
            context.stroke(handlePath, with: .color(.accentColor), lineWidth: 2)
        }
    }

    // MARK: - Coordinate Transformation

    /// Scales a point from image coordinates to view coordinates
    private func scalePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    /// Scales a rect from image coordinates to view coordinates
    private func scaleRect(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let annotations: [Annotation] = [
        .rectangle(RectangleAnnotation(
            rect: CGRect(x: 50, y: 50, width: 100, height: 80),
            style: .default,
            isFilled: false
        )),
        .rectangle(RectangleAnnotation(
            rect: CGRect(x: 200, y: 50, width: 100, height: 80),
            style: StrokeStyle(color: CodableColor(.blue), lineWidth: 3.0),
            isFilled: true
        )),
        .freehand(FreehandAnnotation(
            points: [
                CGPoint(x: 350, y: 100),
                CGPoint(x: 400, y: 150),
                CGPoint(x: 450, y: 120),
                CGPoint(x: 500, y: 180)
            ],
            style: StrokeStyle(color: CodableColor(.green), lineWidth: 3.0)
        )),
        .text(TextAnnotation(
            position: CGPoint(x: 100, y: 200),
            content: "Hello World",
            style: .default
        ))
    ]

    return AnnotationCanvas(
        annotations: annotations,
        currentAnnotation: nil,
        canvasSize: CGSize(width: 800, height: 600),
        scale: 1.0,
        selectedIndex: 0 // Show first annotation selected for preview
    )
    .frame(width: 800, height: 600)
    .background(Color.gray.opacity(0.2))
}
#endif
