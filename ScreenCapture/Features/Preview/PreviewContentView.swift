import SwiftUI
import AppKit

/// SwiftUI view for the screenshot preview content.
/// Displays the captured image with an info bar showing dimensions and file size.
struct PreviewContentView: View {
    // MARK: - Properties

    /// The view model driving this view
    @Bindable var viewModel: PreviewViewModel

    /// Recent captures store for the gallery sidebar
    @ObservedObject var recentCapturesStore: RecentCapturesStore

    /// State for tracking the image display size and scale
    @State private var imageDisplaySize: CGSize = .zero
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGPoint = .zero

    /// Whether to show the recent captures gallery sidebar
    @State private var isShowingGallery: Bool = false

    /// Focus state for the text input field
    @FocusState private var isTextFieldFocused: Bool

    /// Environment variable for Reduce Motion preference
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Initialization

    init(viewModel: PreviewViewModel, recentCapturesStore: RecentCapturesStore = RecentCapturesStore()) {
        self.viewModel = viewModel
        self.recentCapturesStore = recentCapturesStore
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Recent Captures Gallery sidebar (toggleable)
            if isShowingGallery {
                RecentCapturesGallery(
                    store: recentCapturesStore,
                    onSelect: { capture in
                        openCapture(capture)
                    },
                    onReveal: { capture in
                        revealCapture(capture)
                    },
                    onDelete: { capture in
                        recentCapturesStore.remove(capture: capture)
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
            }

            // Main content
            VStack(spacing: 0) {
                // Main image view with annotation canvas
                annotatedImageView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Info bar
                infoBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
        }
        .alert(
            "Error",
            isPresented: .constant(viewModel.errorMessage != nil),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Gallery Actions

    /// Opens a recent capture in Finder (double-click behavior)
    private func openCapture(_ capture: RecentCapture) {
        guard capture.fileExists else { return }
        NSWorkspace.shared.open(capture.filePath)
    }

    /// Reveals a capture in Finder
    private func revealCapture(_ capture: RecentCapture) {
        guard capture.fileExists else { return }
        NSWorkspace.shared.selectFile(capture.filePath.path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Subviews

    /// The main image display area with annotation overlay
    @ViewBuilder
    private var annotatedImageView: some View {
        GeometryReader { geometry in
            let imageSize = CGSize(
                width: CGFloat(viewModel.image.width),
                height: CGFloat(viewModel.image.height)
            )
            let displayInfo = calculateDisplayInfo(
                imageSize: imageSize,
                containerSize: geometry.size
            )

            ZStack {
                // Background
                Color(nsColor: .windowBackgroundColor)

                // Image and annotations centered
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        ZStack(alignment: .topLeading) {
                            // Base image
                            Image(viewModel.image, scale: 1.0, label: Text("Screenshot"))
                                .resizable()
                                .interpolation(.high)  // High quality downscaling
                                .aspectRatio(contentMode: .fit)
                                .frame(
                                    width: displayInfo.displaySize.width,
                                    height: displayInfo.displaySize.height
                                )
                                .accessibilityLabel(Text("Screenshot preview, \(viewModel.dimensionsText), from \(viewModel.displayName)"))

                            // Annotation canvas overlay
                            AnnotationCanvas(
                                annotations: viewModel.annotations,
                                currentAnnotation: viewModel.currentAnnotation,
                                canvasSize: imageSize,
                                scale: displayInfo.scale,
                                selectedIndex: viewModel.selectedAnnotationIndex
                            )
                            .frame(
                                width: displayInfo.displaySize.width,
                                height: displayInfo.displaySize.height
                            )

                            // Text input field overlay (when text tool is active)
                            if viewModel.isWaitingForTextInput,
                               let inputPosition = viewModel.textInputPosition {
                                textInputField(
                                    at: inputPosition,
                                    scale: displayInfo.scale
                                )
                            }

                            // Drawing gesture overlay
                            if viewModel.selectedTool != nil {
                                drawingGestureOverlay(
                                    displaySize: displayInfo.displaySize,
                                    scale: displayInfo.scale
                                )
                            }

                            // Selection/editing gesture overlay (when no tool and no crop mode)
                            if viewModel.selectedTool == nil && !viewModel.isCropMode {
                                selectionGestureOverlay(
                                    displaySize: displayInfo.displaySize,
                                    scale: displayInfo.scale
                                )
                            }

                            // Crop overlay
                            if viewModel.isCropMode {
                                cropOverlay(
                                    displaySize: displayInfo.displaySize,
                                    scale: displayInfo.scale
                                )
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            // Active tool indicator
                            if let tool = viewModel.selectedTool {
                                activeToolIndicator(tool: tool)
                                    .padding(8)
                            } else if viewModel.isCropMode {
                                cropModeIndicator
                                    .padding(8)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            // Crop action buttons
                            if viewModel.cropRect != nil && !viewModel.isCropSelecting {
                                cropActionButtons
                                    .padding(12)
                            }
                        }

                        Spacer()
                    }
                    Spacer()
                }
            }
            .onAppear {
                imageDisplaySize = displayInfo.displaySize
                imageScale = displayInfo.scale
            }
            .onChange(of: geometry.size) { _, newSize in
                let newInfo = calculateDisplayInfo(
                    imageSize: imageSize,
                    containerSize: newSize
                )
                imageDisplaySize = newInfo.displaySize
                imageScale = newInfo.scale
            }
        }
        .contentShape(Rectangle())
        .cursor(cursorForCurrentTool)
    }

    /// Calculates the display size and scale for fitting the image in the container
    private func calculateDisplayInfo(
        imageSize: CGSize,
        containerSize: CGSize
    ) -> (displaySize: CGSize, scale: CGFloat) {
        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = min(widthScale, heightScale, 1.0) // Don't scale up

        let displaySize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return (displaySize, scale)
    }

    /// The cursor to use based on the current tool
    private var cursorForCurrentTool: NSCursor {
        if viewModel.isCropMode {
            return .crosshair
        }

        guard let tool = viewModel.selectedTool else {
            // No tool selected - show move cursor if dragging annotation
            if viewModel.isDraggingAnnotation {
                return .closedHand
            } else if viewModel.selectedAnnotationIndex != nil {
                return .openHand
            }
            return .arrow
        }

        switch tool {
        case .rectangle, .freehand, .arrow:
            return .crosshair
        case .text:
            return .iBeam
        }
    }

    /// Overlay for capturing drawing gestures
    private func drawingGestureOverlay(
        displaySize: CGSize,
        scale: CGFloat
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = convertToImageCoordinates(
                            value.location,
                            scale: scale
                        )

                        if value.translation == .zero {
                            // First point - begin drawing
                            viewModel.beginDrawing(at: point)
                        } else {
                            // Subsequent points - continue drawing
                            viewModel.continueDrawing(to: point)
                        }
                    }
                    .onEnded { value in
                        let point = convertToImageCoordinates(
                            value.location,
                            scale: scale
                        )
                        viewModel.endDrawing(at: point)
                    }
            )
    }

    /// Converts view coordinates to image coordinates
    private func convertToImageCoordinates(
        _ point: CGPoint,
        scale: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: point.x / scale,
            y: point.y / scale
        )
    }

    /// Overlay for selecting and dragging annotations
    private func selectionGestureOverlay(
        displaySize: CGSize,
        scale: CGFloat
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = convertToImageCoordinates(
                            value.location,
                            scale: scale
                        )

                        if value.translation == .zero {
                            // First tap - check for hit
                            if let hitIndex = viewModel.hitTest(at: point) {
                                // Hit an annotation - select it and prepare for dragging
                                viewModel.selectAnnotation(at: hitIndex)
                                viewModel.beginDraggingAnnotation(at: point)
                            } else {
                                // Clicked on empty space - deselect
                                viewModel.deselectAnnotation()
                            }
                        } else if viewModel.isDraggingAnnotation {
                            // Dragging a selected annotation
                            viewModel.continueDraggingAnnotation(to: point)
                        }
                    }
                    .onEnded { _ in
                        viewModel.endDraggingAnnotation()
                    }
            )
    }

    /// Text input field for text annotations
    private func textInputField(
        at position: CGPoint,
        scale: CGFloat
    ) -> some View {
        let scaledPosition = CGPoint(
            x: position.x * scale,
            y: position.y * scale
        )

        return TextField("Enter text", text: $viewModel.textInputContent)
            .textFieldStyle(.plain)
            .font(.system(size: 14 * scale))
            .foregroundColor(AppSettings.shared.strokeColor.color)
            .padding(4)
            .background(Color.white.opacity(0.9))
            .cornerRadius(4)
            .frame(minWidth: 100, maxWidth: 300)
            .position(x: scaledPosition.x + 50, y: scaledPosition.y + 10)
            .focused($isTextFieldFocused)
            .onAppear {
                isTextFieldFocused = true
            }
            .onSubmit {
                viewModel.commitTextInput()
                isTextFieldFocused = false
            }
            .onExitCommand {
                viewModel.cancelCurrentDrawing()
                isTextFieldFocused = false
            }
    }

    /// Active tool indicator badge
    private func activeToolIndicator(tool: AnnotationToolType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: tool.systemImage)
            Text(tool.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Active tool: \(tool.displayName)"))
    }

    /// Crop mode indicator badge
    private var cropModeIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "crop")
            Text("Crop")
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .cornerRadius(6)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Crop mode active"))
    }

    /// Overlay for capturing crop selection gestures
    private func cropOverlay(
        displaySize: CGSize,
        scale: CGFloat
    ) -> some View {
        ZStack {
            // Dim overlay outside crop area
            if let cropRect = viewModel.cropRect, cropRect.width > 0, cropRect.height > 0 {
                let scaledRect = CGRect(
                    x: cropRect.origin.x * scale,
                    y: cropRect.origin.y * scale,
                    width: cropRect.width * scale,
                    height: cropRect.height * scale
                )

                // Create a shape that covers everything except the crop area
                CropDimOverlay(cropRect: scaledRect)
                    .fill(Color.black.opacity(0.5))
                    .allowsHitTesting(false)
                    .transaction { $0.animation = nil }

                // Crop selection border
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: scaledRect.width, height: scaledRect.height)
                    .position(x: scaledRect.midX, y: scaledRect.midY)
                    .allowsHitTesting(false)

                // Corner handles
                ForEach(0..<4, id: \.self) { corner in
                    let position = cornerPosition(for: corner, in: scaledRect)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .position(position)
                        .allowsHitTesting(false)
                }

                // Crop dimensions label
                cropDimensionsLabel(for: cropRect, scaledRect: scaledRect)
            }

            // Gesture capture layer
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = convertToImageCoordinates(value.location, scale: scale)
                            if value.translation == .zero {
                                viewModel.beginCropSelection(at: point)
                            } else {
                                viewModel.continueCropSelection(to: point)
                            }
                        }
                        .onEnded { value in
                            let point = convertToImageCoordinates(value.location, scale: scale)
                            viewModel.endCropSelection(at: point)
                        }
                )
        }
    }

    /// Gets the position for a corner handle
    private func cornerPosition(for corner: Int, in rect: CGRect) -> CGPoint {
        switch corner {
        case 0: return CGPoint(x: rect.minX, y: rect.minY) // Top-left
        case 1: return CGPoint(x: rect.maxX, y: rect.minY) // Top-right
        case 2: return CGPoint(x: rect.minX, y: rect.maxY) // Bottom-left
        case 3: return CGPoint(x: rect.maxX, y: rect.maxY) // Bottom-right
        default: return .zero
        }
    }

    /// Crop dimensions label
    private func cropDimensionsLabel(for cropRect: CGRect, scaledRect: CGRect) -> some View {
        let width = Int(cropRect.width)
        let height = Int(cropRect.height)

        return Text("\(width) × \(height)")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .cornerRadius(4)
            .position(
                x: scaledRect.midX,
                y: max(scaledRect.minY - 20, 15)
            )
            .allowsHitTesting(false)
    }

    /// Crop action buttons (Apply/Cancel)
    private var cropActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.cancelCrop()
            } label: {
                Label("Cancel", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape, modifiers: [])

            Button {
                viewModel.applyCrop()
            } label: {
                Label("Apply Crop", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(10)
    }

    /// The info bar at the bottom showing dimensions and file size
    private var infoBar: some View {
        HStack(spacing: 16) {
            // Dimensions
            Label {
                Text(viewModel.dimensionsText)
                    .font(.system(.body, design: .monospaced))
            } icon: {
                Image(systemName: "aspectratio")
            }
            .foregroundStyle(.secondary)
            .help("Image dimensions in pixels")
            .accessibilityLabel(Text("Dimensions: \(viewModel.dimensionsText)"))

            Divider()
                .frame(height: 16)
                .accessibilityHidden(true)

            // Estimated file size
            Label {
                Text(viewModel.fileSizeText)
                    .font(.system(.body, design: .monospaced))
            } icon: {
                Image(systemName: "doc")
            }
            .foregroundStyle(.secondary)
            .help("Estimated file size")
            .accessibilityLabel(Text("File size: \(viewModel.fileSizeText)"))

            Divider()
                .frame(height: 16)
                .accessibilityHidden(true)

            // Display source
            Label {
                Text(viewModel.displayName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "display")
            }
            .foregroundStyle(.secondary)
            .help("Source display")
            .accessibilityLabel(Text("Source display: \(viewModel.displayName)"))

            Spacer()

            // Tool buttons (for future annotation support)
            toolBar

            Spacer()

            // Action buttons
            actionButtons
        }
    }

    /// Tool selection buttons
    private var toolBar: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationToolType.allCases) { tool in
                let isSelected = viewModel.selectedTool == tool
                Button {
                    if isSelected {
                        viewModel.selectTool(nil)
                    } else {
                        viewModel.selectTool(tool)
                    }
                } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.accessoryBar)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help("\(tool.displayName) (\(String(tool.keyboardShortcut).uppercased()))")
                .accessibilityLabel(Text(tool.displayName))
                .accessibilityHint(Text("Press \(String(tool.keyboardShortcut).uppercased()) to toggle"))
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }

            // Show customization options when a tool is selected OR an annotation is selected
            if viewModel.selectedTool != nil || viewModel.selectedAnnotationIndex != nil {
                Divider()
                    .frame(height: 16)

                styleCustomizationBar
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Annotation tools"))
    }

    /// Style customization bar for color and stroke width
    @ViewBuilder
    private var styleCustomizationBar: some View {
        let isEditingAnnotation = viewModel.selectedAnnotationIndex != nil
        let effectiveToolType = isEditingAnnotation ? viewModel.selectedAnnotationType : viewModel.selectedTool

        HStack(spacing: 8) {
            // Show "Editing" label when modifying existing annotation
            if isEditingAnnotation {
                Text("Edit:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Color picker with preset colors
            HStack(spacing: 2) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        if isEditingAnnotation {
                            viewModel.updateSelectedAnnotationColor(CodableColor(color))
                        } else {
                            AppSettings.shared.strokeColor = CodableColor(color)
                        }
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 16, height: 16)
                            .overlay {
                                let currentColor = isEditingAnnotation
                                    ? (viewModel.selectedAnnotationColor?.color ?? .clear)
                                    : AppSettings.shared.strokeColor.color
                                if colorsAreEqual(currentColor, color) {
                                    Circle()
                                        .stroke(Color.primary, lineWidth: 2)
                                }
                            }
                            .overlay {
                                if color == .white || color == .yellow {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(colorName(for: color))
                }

                ColorPicker("", selection: Binding(
                    get: {
                        if isEditingAnnotation {
                            return viewModel.selectedAnnotationColor?.color ?? .red
                        }
                        return AppSettings.shared.strokeColor.color
                    },
                    set: { newColor in
                        if isEditingAnnotation {
                            viewModel.updateSelectedAnnotationColor(CodableColor(newColor))
                        } else {
                            AppSettings.shared.strokeColor = CodableColor(newColor)
                        }
                    }
                ), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 24)
            }

            Divider()
                .frame(height: 16)

            // Rectangle fill toggle (for rectangle only)
            if effectiveToolType == .rectangle {
                let isFilled = isEditingAnnotation
                    ? (viewModel.selectedAnnotationIsFilled ?? false)
                    : AppSettings.shared.rectangleFilled

                Button {
                    if isEditingAnnotation {
                        viewModel.updateSelectedAnnotationFilled(!isFilled)
                    } else {
                        AppSettings.shared.rectangleFilled.toggle()
                    }
                } label: {
                    Image(systemName: isFilled ? "rectangle.fill" : "rectangle")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.accessoryBar)
                .background(
                    isFilled
                        ? Color.accentColor.opacity(0.2)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help(isFilled ? "Filled (click for hollow)" : "Hollow (click for filled)")

                Divider()
                    .frame(height: 16)
            }

            // Stroke width control (for rectangle/freehand/arrow - only show for hollow rectangles)
            if effectiveToolType == .freehand || effectiveToolType == .arrow ||
               (effectiveToolType == .rectangle && !(isEditingAnnotation ? (viewModel.selectedAnnotationIsFilled ?? false) : AppSettings.shared.rectangleFilled)) {
                HStack(spacing: 4) {
                    Image(systemName: "lineweight")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: {
                                if isEditingAnnotation {
                                    return viewModel.selectedAnnotationStrokeWidth ?? 3.0
                                }
                                return AppSettings.shared.strokeWidth
                            },
                            set: { newWidth in
                                if isEditingAnnotation {
                                    viewModel.updateSelectedAnnotationStrokeWidth(newWidth)
                                } else {
                                    AppSettings.shared.strokeWidth = newWidth
                                }
                            }
                        ),
                        in: 1.0...20.0,
                        step: 0.5
                    )
                    .frame(width: 80)
                    .help("Stroke Width")

                    let width = isEditingAnnotation
                        ? Int(viewModel.selectedAnnotationStrokeWidth ?? 3)
                        : Int(AppSettings.shared.strokeWidth)
                    Text("\(width)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
            }

            // Text size control
            if effectiveToolType == .text {
                HStack(spacing: 4) {
                    Image(systemName: "textformat.size")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: {
                                if isEditingAnnotation {
                                    return viewModel.selectedAnnotationFontSize ?? 16.0
                                }
                                return AppSettings.shared.textSize
                            },
                            set: { newSize in
                                if isEditingAnnotation {
                                    viewModel.updateSelectedAnnotationFontSize(newSize)
                                } else {
                                    AppSettings.shared.textSize = newSize
                                }
                            }
                        ),
                        in: 8.0...72.0,
                        step: 1
                    )
                    .frame(width: 80)
                    .help("Text Size")

                    let size = isEditingAnnotation
                        ? Int(viewModel.selectedAnnotationFontSize ?? 16)
                        : Int(AppSettings.shared.textSize)
                    Text("\(size)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                }
            }

            // Delete button for selected annotation
            if isEditingAnnotation {
                Divider()
                    .frame(height: 16)

                Button {
                    viewModel.deleteSelectedAnnotation()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Delete selected annotation (Delete)")
            }
        }
    }

    /// Preset colors for quick selection
    private var presetColors: [Color] {
        [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]
    }

    /// Compare colors approximately
    private func colorsAreEqual(_ a: Color, _ b: Color) -> Bool {
        let nsA = NSColor(a).usingColorSpace(.deviceRGB)
        let nsB = NSColor(b).usingColorSpace(.deviceRGB)
        guard let colorA = nsA, let colorB = nsB else { return false }

        let tolerance: CGFloat = 0.01
        return abs(colorA.redComponent - colorB.redComponent) < tolerance &&
               abs(colorA.greenComponent - colorB.greenComponent) < tolerance &&
               abs(colorA.blueComponent - colorB.blueComponent) < tolerance
    }

    /// Get accessible color name
    private func colorName(for color: Color) -> String {
        switch color {
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .white: return "White"
        case .black: return "Black"
        default: return "Custom"
        }
    }

    /// Action buttons for save, copy, etc.
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Gallery toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isShowingGallery.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.accessoryBar)
            .background(
                isShowingGallery
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help(isShowingGallery ? "Hide Recent Captures" : "Show Recent Captures (G)")
            .accessibilityLabel(Text(isShowingGallery ? "Hide gallery" : "Show gallery"))

            Divider()
                .frame(height: 16)
                .accessibilityHidden(true)

            // Crop button
            Button {
                viewModel.toggleCropMode()
            } label: {
                Image(systemName: "crop")
            }
            .buttonStyle(.accessoryBar)
            .background(
                viewModel.isCropMode
                    ? Color.accentColor.opacity(0.2)
                    : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("Crop (C)")
            .accessibilityLabel(Text("Crop"))
            .accessibilityHint(Text("Press C to toggle"))

            Divider()
                .frame(height: 16)
                .accessibilityHidden(true)

            // Undo/Redo
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!viewModel.canUndo)
            .help("Undo (⌘Z)")
            .accessibilityLabel(Text("Undo"))
            .accessibilityHint(Text("Command Z"))

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!viewModel.canRedo)
            .help("Redo (⌘⇧Z)")
            .accessibilityLabel(Text("Redo"))
            .accessibilityHint(Text("Command Shift Z"))

            Divider()
                .frame(height: 16)
                .accessibilityHidden(true)

            // Copy to clipboard and dismiss
            Button {
                viewModel.copyToClipboard()
                viewModel.dismiss()
            } label: {
                if viewModel.isCopying {
                    if reduceMotion {
                        Image(systemName: "ellipsis")
                            .frame(width: 16, height: 16)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                } else {
                    Image(systemName: "doc.on.doc")
                }
            }
            .disabled(viewModel.isCopying)
            .help("Copy to Clipboard (⌘C)")
            .accessibilityLabel(Text(viewModel.isCopying ? "Copying to clipboard" : "Copy to clipboard"))
            .accessibilityHint(Text("Command C"))

            // Drag to other apps
            DraggableImageButton(image: viewModel.image, annotations: viewModel.annotations)

            // Save
            Button {
                viewModel.saveScreenshot()
            } label: {
                if viewModel.isSaving {
                    if reduceMotion {
                        Image(systemName: "ellipsis")
                            .frame(width: 16, height: 16)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    }
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .disabled(viewModel.isSaving)
            .help("Save (⌘S or Enter)")
            .accessibilityLabel(Text(viewModel.isSaving ? "Saving screenshot" : "Save screenshot"))
            .accessibilityHint(Text("Command S or Enter"))

            Divider()
                .frame(height: 16)
                .accessibilityHidden(true)

            // Dismiss
            Button {
                viewModel.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Dismiss (Escape)")
            .accessibilityLabel(Text("Dismiss preview"))
            .accessibilityHint(Text("Escape key"))
        }
        .buttonStyle(.accessoryBar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Screenshot actions"))
    }
}

// MARK: - Crop Dim Overlay Shape

/// A shape that covers everything except a rectangular cutout
struct CropDimOverlay: Shape {
    var cropRect: CGRect

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(
                AnimatablePair(cropRect.origin.x, cropRect.origin.y),
                AnimatablePair(cropRect.width, cropRect.height)
            )
        }
        set {
            cropRect = CGRect(
                x: newValue.first.first,
                y: newValue.first.second,
                width: newValue.second.first,
                height: newValue.second.second
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cropRect)
        return path
    }
}

// MARK: - Draggable Image Button

/// A button that can be dragged to other apps to drop the screenshot image.
struct DraggableImageButton: View {
    let image: CGImage
    let annotations: [Annotation]

    @State private var isDragging = false

    var body: some View {
        Button { } label: {
            Image(systemName: "square.and.arrow.up.on.square")
        }
        .buttonStyle(.accessoryBar)
        .background(isDragging ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onDrag {
            isDragging = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isDragging = false
            }
            return createItemProvider()
        }
        .help("Drag to another app")
        .accessibilityLabel(Text("Drag image"))
        .accessibilityHint(Text("Drag to another application to share the screenshot"))
    }

    private func createItemProvider() -> NSItemProvider {
        // Save to a temp file so we can provide a file URL (needed for terminal apps)
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "screenshot_\(Date().timeIntervalSince1970).png"
        let tempURL = tempDir.appendingPathComponent(filename)

        // Render and save the image with annotations
        do {
            try ImageExporter.shared.save(image, annotations: annotations, to: tempURL, format: .png)
        } catch {
            // Fallback: just use the original image without annotations
            if let dest = CGImageDestinationCreateWithURL(tempURL as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(dest, image, nil)
                CGImageDestinationFinalize(dest)
            }
        }

        // Create provider with the file URL - this works with terminals
        let provider = NSItemProvider(contentsOf: tempURL) ?? NSItemProvider()

        // Also register as NSImage for apps that prefer that
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        provider.registerObject(nsImage, visibility: .all)

        return provider
    }

    private func renderImageWithAnnotations() -> CGImage {
        // If no annotations, return original image
        guard !annotations.isEmpty else {
            return image
        }

        // Use a temporary file approach to leverage ImageExporter
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("drag_temp_\(UUID().uuidString).png")

        do {
            try ImageExporter.shared.save(image, annotations: annotations, to: tempURL, format: .png)
            if let data = try? Data(contentsOf: tempURL),
               let provider = CGDataProvider(data: data as CFData),
               let renderedImage = CGImage(
                   pngDataProviderSource: provider,
                   decode: nil,
                   shouldInterpolate: true,
                   intent: .defaultIntent
               ) {
                try? FileManager.default.removeItem(at: tempURL)
                return renderedImage
            }
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            // If export fails, return original image
        }

        return image
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    // Create a simple test image for preview
    let testImage: CGImage = {
        let width = 800
        let height = 600
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Fill with a gradient
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()!
    }()

    let display = DisplayInfo(
        id: 1,
        name: "Built-in Display",
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        scaleFactor: 2.0,
        isPrimary: true
    )

    let screenshot = Screenshot(
        image: testImage,
        sourceDisplay: display
    )

    let viewModel = PreviewViewModel(screenshot: screenshot)

    return PreviewContentView(viewModel: viewModel)
        .frame(width: 600, height: 400)
}
#endif
