import SwiftUI
import AppKit

/// Settings tab enumeration
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case annotations = "Annotations"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .annotations: return "pencil.tip.crop.circle"
        }
    }
}

/// Main settings view with modern tabbed interface.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)

            ShortcutsSettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("Shortcuts", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)

            AnnotationsSettingsTab(viewModel: viewModel)
                .tabItem {
                    Label("Annotations", systemImage: "pencil.tip.crop.circle")
                }
                .tag(SettingsTab.annotations)
        }
        .frame(width: 500, height: 420)
        .alert("Error", isPresented: $viewModel.showErrorAlert) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
    }
}

// MARK: - General Settings Tab

/// General settings including permissions, save location, and export format.
private struct GeneralSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Permissions Card
                SettingsCard(title: "Permissions", icon: "lock.shield") {
                    VStack(spacing: 12) {
                        PermissionRow(
                            icon: "record.circle",
                            title: "Screen Recording",
                            description: "Required to capture screenshots",
                            isGranted: viewModel.hasScreenRecordingPermission,
                            isChecking: viewModel.isCheckingPermissions,
                            onGrant: { viewModel.requestScreenRecordingPermission() }
                        )

                        Divider()

                        PermissionRow(
                            icon: "folder",
                            title: "Save Location",
                            description: "Required to save screenshots",
                            isGranted: viewModel.hasFolderAccessPermission,
                            isChecking: viewModel.isCheckingPermissions,
                            onGrant: { viewModel.requestFolderAccess() }
                        )

                        HStack {
                            Spacer()
                            Button {
                                viewModel.checkPermissions()
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onAppear {
                    viewModel.checkPermissions()
                }

                // Save Location Card
                SettingsCard(title: "Save Location", icon: "folder") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.saveLocationPath)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Button("Choose...") {
                            viewModel.selectSaveLocation()
                        }

                        Button {
                            viewModel.revealSaveLocation()
                        } label: {
                            Image(systemName: "arrow.right.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Reveal in Finder")
                    }
                }

                // Export Format Card
                SettingsCard(title: "Export Format", icon: "photo") {
                    VStack(spacing: 12) {
                        Picker("Format", selection: $viewModel.defaultFormat) {
                            Text("PNG").tag(ExportFormat.png)
                            Text("JPEG").tag(ExportFormat.jpeg)
                        }
                        .pickerStyle(.segmented)

                        if viewModel.defaultFormat == .jpeg {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Quality")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(viewModel.jpegQualityPercentage))%")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }

                                Slider(
                                    value: $viewModel.jpegQuality,
                                    in: SettingsViewModel.jpegQualityRange,
                                    step: 0.05
                                )

                                Text("Higher quality = larger file size")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // Reset Button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.resetAllToDefaults()
                    } label: {
                        Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
                .padding(.top, 8)
            }
            .padding(20)
        }
    }
}

// MARK: - Shortcuts Settings Tab

/// Keyboard shortcuts configuration tab.
private struct ShortcutsSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SettingsCard(title: "Capture Shortcuts", icon: "camera") {
                    VStack(spacing: 16) {
                        ShortcutRow(
                            icon: "rectangle.dashed",
                            label: "Full Screen",
                            shortcut: viewModel.fullScreenShortcut,
                            isRecording: viewModel.isRecordingFullScreenShortcut,
                            onRecord: { viewModel.startRecordingFullScreenShortcut() },
                            onReset: { viewModel.resetFullScreenShortcut() }
                        )

                        Divider()

                        ShortcutRow(
                            icon: "crop",
                            label: "Selection",
                            shortcut: viewModel.selectionShortcut,
                            isRecording: viewModel.isRecordingSelectionShortcut,
                            onRecord: { viewModel.startRecordingSelectionShortcut() },
                            onReset: { viewModel.resetSelectionShortcut() }
                        )

                        Divider()

                        ShortcutRow(
                            icon: "macwindow",
                            label: "Window",
                            shortcut: viewModel.windowShortcut,
                            isRecording: viewModel.isRecordingWindowShortcut,
                            onRecord: { viewModel.startRecordingWindowShortcut() },
                            onReset: { viewModel.resetWindowShortcut() }
                        )

                        Divider()

                        ShortcutRow(
                            icon: "macwindow.on.rectangle",
                            label: "Window + Shadow",
                            shortcut: viewModel.windowWithShadowShortcut,
                            isRecording: viewModel.isRecordingWindowWithShadowShortcut,
                            onRecord: { viewModel.startRecordingWindowWithShadowShortcut() },
                            onReset: { viewModel.resetWindowWithShadowShortcut() }
                        )
                    }
                }

                // Instructions
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Click on a shortcut to change it. Press Escape to cancel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding(20)
        }
    }
}

// MARK: - Annotations Settings Tab

/// Annotation tools configuration tab.
private struct AnnotationsSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Color Selection Card
                SettingsCard(title: "Stroke Color", icon: "paintpalette") {
                    VStack(spacing: 12) {
                        // Preset Colors Grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 9), spacing: 8) {
                            ForEach(SettingsViewModel.presetColors, id: \.self) { color in
                                ColorButton(
                                    color: color,
                                    isSelected: colorsAreEqual(viewModel.strokeColor, color),
                                    action: { viewModel.strokeColor = color }
                                )
                            }
                        }

                        HStack {
                            Text("Custom:")
                                .foregroundStyle(.secondary)
                            ColorPicker("", selection: $viewModel.strokeColor, supportsOpacity: false)
                                .labelsHidden()
                            Spacer()
                        }
                    }
                }

                // Stroke Width Card
                SettingsCard(title: "Stroke Width", icon: "lineweight") {
                    VStack(spacing: 8) {
                        HStack {
                            Slider(
                                value: $viewModel.strokeWidth,
                                in: SettingsViewModel.strokeWidthRange,
                                step: 0.5
                            )

                            Text("\(viewModel.strokeWidth, specifier: "%.1f") pt")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                        }

                        // Visual Preview
                        HStack {
                            Text("Preview:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            RoundedRectangle(cornerRadius: viewModel.strokeWidth / 2)
                                .fill(viewModel.strokeColor)
                                .frame(width: 100, height: max(viewModel.strokeWidth, 2))
                        }
                    }
                }

                // Text Size Card
                SettingsCard(title: "Text Size", icon: "textformat.size") {
                    VStack(spacing: 8) {
                        HStack {
                            Slider(
                                value: $viewModel.textSize,
                                in: SettingsViewModel.textSizeRange,
                                step: 1
                            )

                            Text("\(Int(viewModel.textSize)) pt")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 60, alignment: .trailing)
                        }

                        // Visual Preview
                        HStack {
                            Text("Preview:")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Aa")
                                .font(.system(size: min(viewModel.textSize, 32)))
                                .foregroundStyle(viewModel.strokeColor)
                        }
                    }
                }
            }
            .padding(20)
        }
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
}

// MARK: - Reusable Components

/// A card container for settings sections.
private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// A single permission row with status and action.
private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isChecking: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                if !isGranted && !isChecking {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isChecking {
                ProgressView()
                    .controlSize(.small)
            } else if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Grant") {
                    onGrant()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

/// A single shortcut configuration row.
private struct ShortcutRow: View {
    let icon: String
    let label: String
    let shortcut: KeyboardShortcut
    let isRecording: Bool
    let onRecord: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(label)

            Spacer()

            Button {
                onRecord()
            } label: {
                HStack(spacing: 4) {
                    if isRecording {
                        Text("Recording...")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(shortcut.displayString)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button {
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Reset to default")
            .disabled(isRecording)
        }
    }
}

/// A color selection button.
private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.primary, lineWidth: 2.5)
                            .padding(2)
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
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    SettingsView(viewModel: SettingsViewModel())
}
#endif
