import Foundation
import SwiftUI
import AppKit
import Observation

/// ViewModel for the screenshot preview window.
/// Manages screenshot state, annotations, and user actions.
/// Must run on MainActor for UI binding.
@MainActor
@Observable
final class PreviewViewModel {
    // MARK: - Properties

    /// The current screenshot being previewed
    private(set) var screenshot: Screenshot

    /// Whether the preview is currently visible (internal state, not observed)
    @ObservationIgnored
    private(set) var isVisible: Bool = false

    /// Current annotation tool selection (nil = no tool active)
    var selectedTool: AnnotationToolType? {
        didSet {
            // Cancel any in-progress drawing when switching tools
            if oldValue != selectedTool {
                cancelCurrentDrawing()
            }
            // Exit crop mode when selecting an annotation tool
            if selectedTool != nil && isCropMode {
                isCropMode = false
                cropRect = nil
            }
        }
    }

    /// Whether crop mode is active
    var isCropMode: Bool = false {
        didSet {
            // Deselect annotation tool when entering crop mode
            if isCropMode && selectedTool != nil {
                selectedTool = nil
            }
            if !isCropMode {
                cropRect = nil
            }
        }
    }

    /// The current crop selection rectangle (in image coordinates)
    var cropRect: CGRect?

    /// Whether a crop selection is in progress
    var isCropSelecting: Bool = false

    /// Start point of crop selection
    private var cropStartPoint: CGPoint?

    /// Error message to display (if any)
    var errorMessage: String?

    /// Whether save is in progress
    private(set) var isSaving: Bool = false

    /// Whether copy is in progress
    private(set) var isCopying: Bool = false

    /// Callback when the preview should be dismissed
    @ObservationIgnored
    var onDismiss: (() -> Void)?

    /// Callback when screenshot is saved successfully
    @ObservationIgnored
    var onSave: ((URL) -> Void)?

    /// App settings for default export options
    @ObservationIgnored
    private let settings = AppSettings.shared

    /// Image exporter for saving screenshots
    @ObservationIgnored
    private let imageExporter = ImageExporter.shared

    /// Clipboard service for copying screenshots
    @ObservationIgnored
    private let clipboardService = ClipboardService.shared

    /// Recent captures store
    @ObservationIgnored
    private let recentCapturesStore: RecentCapturesStore

    // MARK: - Annotation Tools

    /// Rectangle drawing tool
    @ObservationIgnored
    private(set) var rectangleTool = RectangleTool()

    /// Freehand drawing tool
    @ObservationIgnored
    private(set) var freehandTool = FreehandTool()

    /// Arrow drawing tool
    @ObservationIgnored
    private(set) var arrowTool = ArrowTool()

    /// Text placement tool
    @ObservationIgnored
    private(set) var textTool = TextTool()

    /// Blur tool
    @ObservationIgnored
    private(set) var blurTool = BlurTool()

    /// Counter to trigger view updates during drawing
    /// Incremented each time drawing state changes to force re-render
    private(set) var drawingUpdateCounter: Int = 0

    /// Cached current annotation for observation
    private(set) var _currentAnnotation: Annotation?

    /// Observable state for text input visibility (since textTool is @ObservationIgnored)
    private(set) var _isWaitingForTextInput: Bool = false

    /// Observable position for text input field
    private(set) var _textInputPosition: CGPoint?

    // MARK: - Annotation Selection & Editing

    /// Index of the currently selected annotation (nil = none selected)
    var selectedAnnotationIndex: Int?

    /// Whether we're currently dragging a selected annotation
    private(set) var isDraggingAnnotation: Bool = false

    /// The starting point of a drag operation (in image coordinates)
    @ObservationIgnored
    private var dragStartPoint: CGPoint?

    /// The original position of the annotation being dragged
    @ObservationIgnored
    private var dragOriginalPosition: CGPoint?

    /// Whether any tool is currently drawing
    var isDrawing: Bool {
        currentTool?.isActive ?? false
    }

    /// The current in-progress annotation for preview
    var currentAnnotation: Annotation? {
        _currentAnnotation
    }

    /// The currently active tool instance
    private var currentTool: (any AnnotationTool)? {
        guard let selectedTool else { return nil }
        switch selectedTool {
        case .rectangle: return rectangleTool
        case .freehand: return freehandTool
        case .arrow: return arrowTool
        case .text: return textTool
        case .blur: return blurTool
        }
    }

    /// Whether we're waiting for text input
    var isWaitingForTextInput: Bool {
        _isWaitingForTextInput
    }

    /// The current text input content
    var textInputContent: String {
        get { textTool.currentText }
        set { textTool.updateText(newValue) }
    }

    /// The position for text input field
    var textInputPosition: CGPoint? {
        _textInputPosition
    }

    // MARK: - Computed Properties

    /// The CGImage being previewed
    var image: CGImage {
        screenshot.image
    }

    /// Current annotations on the screenshot
    var annotations: [Annotation] {
        screenshot.annotations
    }

    /// Formatted dimensions string (e.g., "1920 × 1080")
    var dimensionsText: String {
        screenshot.formattedDimensions
    }

    /// Formatted estimated file size (e.g., "1.2 MB")
    var fileSizeText: String {
        // Use the actual format from settings for accurate estimation
        let format = settings.defaultFormat
        let pixelCount = Double(screenshot.image.width * screenshot.image.height)
        let bytes = Int(pixelCount * format.estimatedBytesPerPixel)

        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }

    /// Source display name
    var displayName: String {
        screenshot.sourceDisplay.name
    }

    /// Source display scale factor (for Retina displays)
    var sourceScaleFactor: CGFloat {
        screenshot.sourceDisplay.scaleFactor
    }

    /// Current export format
    var format: ExportFormat {
        get { screenshot.format }
        set { screenshot = screenshot.with(format: newValue) }
    }

    /// Whether undo is available
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Whether redo is available
    var canRedo: Bool {
        !redoStack.isEmpty
    }

    // MARK: - Undo/Redo

    /// Stack of previous screenshot states for undo (includes image + annotations)
    private var undoStack: [Screenshot] = []

    /// Stack of undone screenshot states for redo
    private var redoStack: [Screenshot] = []

    /// Maximum undo history
    @ObservationIgnored
    private let maxUndoLevels = 50

    /// Counter that increments when image size changes (for window resize notification)
    private(set) var imageSizeChangeCounter: Int = 0

    // MARK: - Initialization

    init(screenshot: Screenshot, recentCapturesStore: RecentCapturesStore? = nil) {
        self.screenshot = screenshot
        self.recentCapturesStore = recentCapturesStore ?? RecentCapturesStore()
    }

    // MARK: - Public API

    /// Shows the preview window
    func show() {
        isVisible = true
    }

    /// Hides the preview window
    func hide() {
        // Guard against recursive calls
        guard isVisible else { return }
        isVisible = false
        onDismiss?()
    }

    /// Loads a recent capture into the editor for editing
    func loadCapture(_ capture: RecentCapture) {
        guard capture.fileExists else { return }

        // Load image from file
        guard let nsImage = NSImage(contentsOf: capture.filePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        // Clear undo/redo stacks
        undoStack.removeAll()
        redoStack.removeAll()

        // Create new screenshot with the loaded image
        screenshot = Screenshot(
            image: cgImage,
            captureDate: capture.captureDate,
            sourceDisplay: DisplayInfo(
                id: 0,
                name: "Recent Capture",
                frame: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height),
                scaleFactor: 1.0,
                isPrimary: true
            ),
            filePath: capture.filePath
        )

        // Reset tool state
        selectedTool = nil
        _currentAnnotation = nil
        selectedAnnotationIndex = nil
        isCropMode = false
        cropRect = nil
    }

    /// Adds an annotation to the screenshot
    func addAnnotation(_ annotation: Annotation) {
        pushUndoState()
        screenshot = screenshot.adding(annotation)
        redoStack.removeAll()
    }

    /// Removes the annotation at the given index
    func removeAnnotation(at index: Int) {
        guard index >= 0 && index < annotations.count else { return }
        pushUndoState()
        screenshot = screenshot.removingAnnotation(at: index)
        redoStack.removeAll()
    }

    /// Undoes the last change (annotation or crop)
    func undo() {
        guard let previousState = undoStack.popLast() else { return }

        // Check if image size will change
        let currentSize = CGSize(width: screenshot.image.width, height: screenshot.image.height)
        let previousSize = CGSize(width: previousState.image.width, height: previousState.image.height)
        let imageSizeChanged = currentSize != previousSize

        redoStack.append(screenshot)
        screenshot = previousState

        // Notify if image size changed (for window resize)
        if imageSizeChanged {
            imageSizeChangeCounter += 1
        }
    }

    /// Redoes the last undone change
    func redo() {
        guard let nextState = redoStack.popLast() else { return }

        // Check if image size will change
        let currentSize = CGSize(width: screenshot.image.width, height: screenshot.image.height)
        let nextSize = CGSize(width: nextState.image.width, height: nextState.image.height)
        let imageSizeChanged = currentSize != nextSize

        undoStack.append(screenshot)
        screenshot = nextState

        // Notify if image size changed (for window resize)
        if imageSizeChanged {
            imageSizeChangeCounter += 1
        }
    }

    /// Selects an annotation tool
    func selectTool(_ tool: AnnotationToolType?) {
        selectedTool = tool
    }

    // MARK: - Drawing Methods

    /// Begins a drawing gesture at the given point
    /// - Parameter point: The point in image coordinates
    func beginDrawing(at point: CGPoint) {
        guard let selectedTool else { return }

        // Apply current stroke/text styles from settings
        let strokeStyle = StrokeStyle(
            color: settings.strokeColor,
            lineWidth: settings.strokeWidth
        )
        let textStyle = TextStyle(
            color: settings.strokeColor,
            fontSize: settings.textSize,
            fontName: ".AppleSystemUIFont"
        )

        switch selectedTool {
        case .rectangle:
            rectangleTool.strokeStyle = strokeStyle
            rectangleTool.isFilled = settings.rectangleFilled
            rectangleTool.beginDrawing(at: point)
        case .freehand:
            freehandTool.strokeStyle = strokeStyle
            freehandTool.beginDrawing(at: point)
        case .arrow:
            arrowTool.strokeStyle = strokeStyle
            arrowTool.beginDrawing(at: point)
        case .text:
            textTool.textStyle = textStyle
            textTool.beginDrawing(at: point)
            // Update observable properties for text input UI
            _isWaitingForTextInput = true
            _textInputPosition = point
        case .blur:
            // Read directly from shared settings to ensure we get the latest values
            blurTool.blurRadius = AppSettings.shared.blurRadius
            blurTool.brushSize = AppSettings.shared.strokeWidth * 10  // Use stroke width scaled up for brush
            blurTool.beginDrawing(at: point)
        }

        updateCurrentAnnotation()
    }

    /// Continues a drawing gesture to the given point
    /// - Parameter point: The point in image coordinates
    func continueDrawing(to point: CGPoint) {
        guard let selectedTool else { return }

        switch selectedTool {
        case .rectangle:
            rectangleTool.continueDrawing(to: point)
        case .freehand:
            freehandTool.continueDrawing(to: point)
        case .arrow:
            arrowTool.continueDrawing(to: point)
        case .text:
            textTool.continueDrawing(to: point)
        case .blur:
            blurTool.continueDrawing(to: point)
        }

        updateCurrentAnnotation()
    }

    /// Ends a drawing gesture at the given point
    /// - Parameter point: The point in image coordinates
    func endDrawing(at point: CGPoint) {
        guard let selectedTool else { return }

        var annotation: Annotation?

        switch selectedTool {
        case .rectangle:
            annotation = rectangleTool.endDrawing(at: point)
        case .freehand:
            annotation = freehandTool.endDrawing(at: point)
        case .arrow:
            annotation = arrowTool.endDrawing(at: point)
        case .text:
            // Text tool doesn't finish on mouse up
            _ = textTool.endDrawing(at: point)
            updateCurrentAnnotation()
            return
        case .blur:
            annotation = blurTool.endDrawing(at: point)
        }

        _currentAnnotation = nil
        drawingUpdateCounter += 1

        if let annotation {
            addAnnotation(annotation)
        }
    }

    /// Cancels the current drawing operation
    func cancelCurrentDrawing() {
        rectangleTool.cancelDrawing()
        freehandTool.cancelDrawing()
        arrowTool.cancelDrawing()
        textTool.cancelDrawing()
        blurTool.cancelDrawing()
        _currentAnnotation = nil
        _isWaitingForTextInput = false
        _textInputPosition = nil
        drawingUpdateCounter += 1
    }

    /// Updates the cached current annotation to trigger view refresh
    private func updateCurrentAnnotation() {
        _currentAnnotation = currentTool?.currentAnnotation
        drawingUpdateCounter += 1
    }

    // MARK: - Crop Methods

    /// Toggles crop mode
    func toggleCropMode() {
        isCropMode.toggle()
    }

    /// Begins a crop selection at the given point
    func beginCropSelection(at point: CGPoint) {
        guard isCropMode else { return }
        cropStartPoint = point
        cropRect = CGRect(origin: point, size: .zero)
        isCropSelecting = true
    }

    /// Continues a crop selection to the given point
    func continueCropSelection(to point: CGPoint) {
        guard isCropMode, let start = cropStartPoint else { return }

        let minX = min(start.x, point.x)
        let minY = min(start.y, point.y)
        let width = abs(point.x - start.x)
        let height = abs(point.y - start.y)

        cropRect = CGRect(x: minX, y: minY, width: width, height: height)
    }

    /// Ends a crop selection
    func endCropSelection(at point: CGPoint) {
        guard isCropMode else { return }
        continueCropSelection(to: point)
        isCropSelecting = false

        // Validate minimum crop size
        if let rect = cropRect, rect.width < 10 || rect.height < 10 {
            cropRect = nil
        }
    }

    /// Applies the current crop selection
    func applyCrop() {
        guard let rect = cropRect else { return }

        // Ensure crop rect is within image bounds
        let imageWidth = CGFloat(screenshot.image.width)
        let imageHeight = CGFloat(screenshot.image.height)

        let clampedRect = CGRect(
            x: max(0, rect.origin.x),
            y: max(0, rect.origin.y),
            width: min(rect.width, imageWidth - rect.origin.x),
            height: min(rect.height, imageHeight - rect.origin.y)
        )

        guard clampedRect.width >= 10, clampedRect.height >= 10 else {
            errorMessage = "Crop area is too small"
            cropRect = nil
            isCropMode = false
            return
        }

        // Create cropped image
        guard let croppedImage = screenshot.image.cropping(to: clampedRect) else {
            errorMessage = "Failed to crop image"
            return
        }

        // Push undo state before cropping
        pushUndoState()

        // Update screenshot with cropped image and clear annotations
        // (annotations would need to be recalculated for the new crop, so we clear them)
        screenshot = Screenshot(
            image: croppedImage,
            captureDate: screenshot.captureDate,
            sourceDisplay: screenshot.sourceDisplay
        )

        // Clear redo stack since we made a change
        redoStack.removeAll()

        // Exit crop mode
        isCropMode = false
        cropRect = nil
        // Note: We don't increment imageSizeChangeCounter here because
        // crop should not resize the window, only the image within it
    }

    /// Cancels the current crop selection
    func cancelCrop() {
        cropRect = nil
        isCropMode = false
        isCropSelecting = false
        cropStartPoint = nil
    }

    // MARK: - Annotation Selection & Editing

    /// Tests if a point hits an annotation and returns its index
    /// - Parameter point: The point to test in image coordinates
    /// - Returns: The index of the hit annotation, or nil if none hit
    func hitTest(at point: CGPoint) -> Int? {
        // Check in reverse order (top-most first)
        for (index, annotation) in annotations.enumerated().reversed() {
            let bounds = annotation.bounds
            // Add some padding for easier selection
            let expandedBounds = bounds.insetBy(dx: -10, dy: -10)
            if expandedBounds.contains(point) {
                return index
            }
        }
        return nil
    }

    /// Selects the annotation at the given index
    func selectAnnotation(at index: Int?) {
        // Deselect any tool when selecting an annotation
        if index != nil && selectedTool != nil {
            selectedTool = nil
        }
        selectedAnnotationIndex = index
    }

    /// Deselects any selected annotation
    func deselectAnnotation() {
        selectedAnnotationIndex = nil
        isDraggingAnnotation = false
        dragStartPoint = nil
        dragOriginalPosition = nil
    }

    /// Deletes the currently selected annotation
    func deleteSelectedAnnotation() {
        guard let index = selectedAnnotationIndex else { return }
        pushUndoState()
        screenshot = screenshot.removingAnnotation(at: index)
        redoStack.removeAll()
        selectedAnnotationIndex = nil
    }

    /// Begins dragging the selected annotation
    func beginDraggingAnnotation(at point: CGPoint) {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return }

        isDraggingAnnotation = true
        dragStartPoint = point

        // Store the original position based on annotation type
        let annotation = annotations[index]
        switch annotation {
        case .rectangle(let rect):
            dragOriginalPosition = rect.rect.origin
        case .freehand(let freehand):
            dragOriginalPosition = freehand.bounds.origin
        case .arrow(let arrow):
            dragOriginalPosition = arrow.bounds.origin
        case .text(let text):
            dragOriginalPosition = text.position
        case .blur(let blur):
            dragOriginalPosition = blur.rect.origin
        }
    }

    /// Continues dragging the selected annotation
    func continueDraggingAnnotation(to point: CGPoint) {
        guard isDraggingAnnotation,
              let index = selectedAnnotationIndex,
              let startPoint = dragStartPoint,
              let originalPosition = dragOriginalPosition,
              index < annotations.count else { return }

        let delta = CGPoint(
            x: point.x - startPoint.x,
            y: point.y - startPoint.y
        )

        let annotation = annotations[index]
        var updatedAnnotation: Annotation?

        switch annotation {
        case .rectangle(var rect):
            rect.rect.origin = CGPoint(
                x: originalPosition.x + delta.x,
                y: originalPosition.y + delta.y
            )
            updatedAnnotation = .rectangle(rect)

        case .freehand(var freehand):
            // Move all points by the delta
            let bounds = freehand.bounds
            let offsetX = originalPosition.x + delta.x - bounds.origin.x
            let offsetY = originalPosition.y + delta.y - bounds.origin.y
            freehand.points = freehand.points.map { point in
                CGPoint(x: point.x + offsetX, y: point.y + offsetY)
            }
            updatedAnnotation = .freehand(freehand)

        case .arrow(var arrow):
            // Move both start and end points by the delta
            let bounds = arrow.bounds
            let offsetX = originalPosition.x + delta.x - bounds.origin.x
            let offsetY = originalPosition.y + delta.y - bounds.origin.y
            arrow.startPoint = CGPoint(
                x: arrow.startPoint.x + offsetX,
                y: arrow.startPoint.y + offsetY
            )
            arrow.endPoint = CGPoint(
                x: arrow.endPoint.x + offsetX,
                y: arrow.endPoint.y + offsetY
            )
            updatedAnnotation = .arrow(arrow)

        case .text(var text):
            text.position = CGPoint(
                x: originalPosition.x + delta.x,
                y: originalPosition.y + delta.y
            )
            updatedAnnotation = .text(text)

        case .blur(var blur):
            // Translate all points
            blur.points = blur.points.map { point in
                CGPoint(
                    x: point.x + delta.x,
                    y: point.y + delta.y
                )
            }
            updatedAnnotation = .blur(blur)
        }

        if let updated = updatedAnnotation {
            // Update without pushing undo (will push on end)
            screenshot.annotations[index] = updated
            drawingUpdateCounter += 1
        }
    }

    /// Ends dragging the selected annotation
    func endDraggingAnnotation() {
        isDraggingAnnotation = false
        dragStartPoint = nil
        dragOriginalPosition = nil
    }

    /// Updates the color of the selected annotation
    func updateSelectedAnnotationColor(_ color: CodableColor) {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return }

        pushUndoState()
        let annotation = annotations[index]
        var updatedAnnotation: Annotation?

        switch annotation {
        case .rectangle(var rect):
            rect.style.color = color
            updatedAnnotation = .rectangle(rect)

        case .freehand(var freehand):
            freehand.style.color = color
            updatedAnnotation = .freehand(freehand)

        case .arrow(var arrow):
            arrow.style.color = color
            updatedAnnotation = .arrow(arrow)

        case .text(var text):
            text.style.color = color
            updatedAnnotation = .text(text)

        case .blur:
            // Blur doesn't have a color
            return
        }

        if let updated = updatedAnnotation {
            screenshot = screenshot.replacingAnnotation(at: index, with: updated)
            redoStack.removeAll()
        }
    }

    /// Updates the stroke width of the selected annotation (rectangle/freehand/arrow)
    func updateSelectedAnnotationStrokeWidth(_ width: CGFloat) {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return }

        pushUndoState()
        let annotation = annotations[index]
        var updatedAnnotation: Annotation?

        switch annotation {
        case .rectangle(var rect):
            rect.style.lineWidth = width
            updatedAnnotation = .rectangle(rect)

        case .freehand(var freehand):
            freehand.style.lineWidth = width
            updatedAnnotation = .freehand(freehand)

        case .arrow(var arrow):
            arrow.style.lineWidth = width
            updatedAnnotation = .arrow(arrow)

        case .text:
            // Text doesn't have stroke width
            return

        case .blur:
            // Blur doesn't have stroke width
            return
        }

        if let updated = updatedAnnotation {
            screenshot = screenshot.replacingAnnotation(at: index, with: updated)
            redoStack.removeAll()
        }
    }

    /// Updates the font size of the selected text annotation
    func updateSelectedAnnotationFontSize(_ size: CGFloat) {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return }

        let annotation = annotations[index]
        guard case .text(var text) = annotation else { return }

        pushUndoState()
        text.style.fontSize = size
        screenshot = screenshot.replacingAnnotation(at: index, with: .text(text))
        redoStack.removeAll()
    }

    /// Returns the type of the selected annotation
    var selectedAnnotationType: AnnotationToolType? {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return nil }

        switch annotations[index] {
        case .rectangle: return .rectangle
        case .freehand: return .freehand
        case .arrow: return .arrow
        case .text: return .text
        case .blur: return .blur
        }
    }

    /// Returns the color of the selected annotation
    var selectedAnnotationColor: CodableColor? {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return nil }

        switch annotations[index] {
        case .rectangle(let rect): return rect.style.color
        case .freehand(let freehand): return freehand.style.color
        case .arrow(let arrow): return arrow.style.color
        case .text(let text): return text.style.color
        case .blur: return nil  // Blur doesn't have a color
        }
    }

    /// Returns the stroke width of the selected annotation (rectangle/freehand/arrow)
    var selectedAnnotationStrokeWidth: CGFloat? {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return nil }

        switch annotations[index] {
        case .rectangle(let rect): return rect.style.lineWidth
        case .freehand(let freehand): return freehand.style.lineWidth
        case .arrow(let arrow): return arrow.style.lineWidth
        case .text: return nil
        case .blur: return nil  // Blur doesn't have stroke width
        }
    }

    /// Returns the font size of the selected text annotation
    var selectedAnnotationFontSize: CGFloat? {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return nil }

        if case .text(let text) = annotations[index] {
            return text.style.fontSize
        }
        return nil
    }

    /// Returns the isFilled state of the selected rectangle annotation
    var selectedAnnotationIsFilled: Bool? {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return nil }

        if case .rectangle(let rect) = annotations[index] {
            return rect.isFilled
        }
        return nil
    }

    /// Updates the isFilled state of the selected rectangle annotation
    func updateSelectedAnnotationFilled(_ isFilled: Bool) {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return }

        let annotation = annotations[index]
        guard case .rectangle(var rect) = annotation else { return }

        pushUndoState()
        rect.isFilled = isFilled
        screenshot = screenshot.replacingAnnotation(at: index, with: .rectangle(rect))
        redoStack.removeAll()
    }

    /// Returns the blur radius of the selected blur annotation
    var selectedAnnotationBlurRadius: CGFloat? {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return nil }

        if case .blur(let blur) = annotations[index] {
            return blur.blurRadius
        }
        return nil
    }

    /// Updates the blur radius of the selected blur annotation
    func updateSelectedAnnotationBlurRadius(_ radius: CGFloat) {
        guard let index = selectedAnnotationIndex,
              index < annotations.count else { return }

        let annotation = annotations[index]
        guard case .blur(var blur) = annotation else { return }

        pushUndoState()
        blur.blurRadius = radius
        screenshot = screenshot.replacingAnnotation(at: index, with: .blur(blur))
        redoStack.removeAll()
    }

    /// Commits the current text input and adds the annotation
    func commitTextInput() {
        if let annotation = textTool.commitText() {
            addAnnotation(annotation)
        }
        // Reset observable text input state
        _isWaitingForTextInput = false
        _textInputPosition = nil
    }

    /// Dismisses the preview - auto-saves before closing if enabled
    func dismiss() {
        // Auto-save if enabled and not already saved
        if settings.autoSaveOnClose && screenshot.filePath == nil && !isSaving {
            saveScreenshot()
        } else {
            hide()
        }
    }

    /// Copies the screenshot to clipboard (Cmd+C action)
    func copyToClipboard() {
        guard !isCopying else { return }
        isCopying = true

        do {
            try clipboardService.copy(image, annotations: annotations)
        } catch {
            errorMessage = NSLocalizedString("error.clipboard.write.failed", comment: "Failed to copy to clipboard")
            clearError()
        }

        isCopying = false
    }

    /// Saves the screenshot to the default location (Enter/Cmd+S action)
    func saveScreenshot() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            await performSave()
        }
    }

    /// Performs the actual save operation
    private func performSave() async {
        defer { isSaving = false }

        let directory = settings.saveLocation
        let format = settings.defaultFormat
        let quality = settings.jpegQuality

        // Generate file URL
        let fileURL = imageExporter.generateFileURL(in: directory, format: format)

        do {
            try imageExporter.save(
                image,
                annotations: annotations,
                to: fileURL,
                format: format,
                quality: quality
            )

            // Update screenshot with file path
            screenshot = screenshot.saved(to: fileURL)

            // Add to recent captures
            recentCapturesStore.add(filePath: fileURL, image: image)

            // Notify callback
            onSave?(fileURL)

            // Dismiss the preview after successful save
            hide()
        } catch let error as ScreenCaptureError {
            handleSaveError(error)
        } catch {
            errorMessage = NSLocalizedString("error.save.unknown", comment: "An unexpected error occurred while saving")
            clearError()
        }
    }

    /// Handles save errors with user-friendly messages
    private func handleSaveError(_ error: ScreenCaptureError) {
        switch error {
        case .invalidSaveLocation(let url):
            errorMessage = String(
                format: NSLocalizedString("error.save.location.invalid.detail", comment: ""),
                url.path
            )
        case .diskFull:
            errorMessage = NSLocalizedString("error.disk.full", comment: "Not enough disk space")
        case .exportEncodingFailed(let format):
            errorMessage = String(
                format: NSLocalizedString("error.export.encoding.failed.detail", comment: ""),
                format.displayName
            )
        default:
            errorMessage = error.localizedDescription
        }
        clearError()
    }

    // MARK: - Private Methods

    /// Pushes the current screenshot state to the undo stack
    private func pushUndoState() {
        undoStack.append(screenshot)

        // Limit undo history
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
    }

    /// Clears error message after delay
    private func clearError() {
        Task {
            try? await Task.sleep(for: .seconds(3))
            errorMessage = nil
        }
    }
}

// MARK: - Annotation Tool Type

/// Available annotation tool types for the preview
enum AnnotationToolType: String, CaseIterable, Identifiable, Sendable {
    case rectangle
    case freehand
    case arrow
    case text
    case blur

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .freehand: return "Draw"
        case .arrow: return "Arrow"
        case .text: return "Text"
        case .blur: return "Blur"
        }
    }

    var keyboardShortcut: Character {
        switch self {
        case .rectangle: return "r"
        case .freehand: return "d"
        case .arrow: return "a"
        case .text: return "t"
        case .blur: return "b"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .freehand: return "pencil.line"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .blur: return "eye.slash"
        }
    }
}
