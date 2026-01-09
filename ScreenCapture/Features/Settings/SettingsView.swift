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
        .frame(width: 560, height: 640)
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
            VStack(spacing: 16) {
                // Permissions Section
                SettingsSection(title: "Permissions") {
                    VStack(spacing: 0) {
                        PermissionRow(
                            icon: "record.circle",
                            title: "Screen Recording",
                            isGranted: viewModel.hasScreenRecordingPermission,
                            isChecking: viewModel.isCheckingPermissions,
                            onGrant: { viewModel.requestScreenRecordingPermission() }
                        )

                        Divider()
                            .padding(.leading, 44)

                        PermissionRow(
                            icon: "folder",
                            title: "File Access",
                            isGranted: viewModel.hasFolderAccessPermission,
                            isChecking: viewModel.isCheckingPermissions,
                            onGrant: { viewModel.requestFolderAccess() }
                        )
                    }
                }
                .onAppear {
                    viewModel.checkPermissions()
                }

                // Save Location Section
                SettingsSection(title: "Save Location") {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        Text(viewModel.saveLocationPath)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Change...") {
                            viewModel.selectSaveLocation()
                        }
                        .buttonStyle(.bordered)

                        Button {
                            viewModel.revealSaveLocation()
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                    .padding(.vertical, 4)
                }

                // Export Format Section
                SettingsSection(title: "Export Format") {
                    VStack(spacing: 14) {
                        Picker("Format", selection: $viewModel.defaultFormat) {
                            Text("PNG").tag(ExportFormat.png)
                            Text("JPEG").tag(ExportFormat.jpeg)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if viewModel.defaultFormat == .jpeg {
                            VStack(spacing: 10) {
                                HStack {
                                    Text("Quality")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(viewModel.jpegQualityPercentage))%")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.primary)
                                }

                                Slider(
                                    value: $viewModel.jpegQuality,
                                    in: SettingsViewModel.jpegQualityRange,
                                    step: 0.05
                                )
                                .tint(.blue)
                            }
                        }
                    }
                }

                // Startup Section
                SettingsSection(title: "Startup") {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login")
                                    .font(.body)
                                Text("Start ScreenCapture when you log in")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $viewModel.launchAtLogin)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Divider()
                            .padding(.vertical, 10)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-save on Close")
                                    .font(.body)
                                Text("Save screenshots automatically when closing preview")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $viewModel.autoSaveOnClose)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                }

                Spacer(minLength: 8)

                // Reset Button
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.resetAllToDefaults()
                    } label: {
                        Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Shortcuts Settings Tab

/// Keyboard shortcuts configuration tab.
private struct ShortcutsSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsSection(title: "Capture Shortcuts") {
                    VStack(spacing: 0) {
                        ShortcutRow(
                            icon: "rectangle.dashed",
                            label: "Full Screen",
                            shortcut: viewModel.fullScreenShortcut,
                            isRecording: viewModel.isRecordingFullScreenShortcut,
                            onRecord: { viewModel.startRecordingFullScreenShortcut() },
                            onReset: { viewModel.resetFullScreenShortcut() }
                        )

                        Divider().padding(.leading, 44)

                        ShortcutRow(
                            icon: "crop",
                            label: "Selection",
                            shortcut: viewModel.selectionShortcut,
                            isRecording: viewModel.isRecordingSelectionShortcut,
                            onRecord: { viewModel.startRecordingSelectionShortcut() },
                            onReset: { viewModel.resetSelectionShortcut() }
                        )

                        Divider().padding(.leading, 44)

                        ShortcutRow(
                            icon: "macwindow",
                            label: "Window",
                            shortcut: viewModel.windowShortcut,
                            isRecording: viewModel.isRecordingWindowShortcut,
                            onRecord: { viewModel.startRecordingWindowShortcut() },
                            onReset: { viewModel.resetWindowShortcut() }
                        )

                        Divider().padding(.leading, 44)

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
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue.opacity(0.7))
                    Text("Click a shortcut to change it. Press Escape to cancel.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
            }
            .padding(24)
        }
    }
}

// MARK: - Annotations Settings Tab

/// Annotation tools configuration tab.
private struct AnnotationsSettingsTab: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Color Selection
                SettingsSection(title: "Stroke Color") {
                    VStack(spacing: 14) {
                        // Preset Colors Grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 9), spacing: 10) {
                            ForEach(SettingsViewModel.presetColors, id: \.self) { color in
                                ColorButton(
                                    color: color,
                                    isSelected: colorsAreEqual(viewModel.strokeColor, color),
                                    action: { viewModel.strokeColor = color }
                                )
                            }
                        }

                        Divider()

                        HStack {
                            Text("Custom Color")
                                .foregroundStyle(.secondary)
                            Spacer()
                            ColorPicker("", selection: $viewModel.strokeColor, supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                }

                // Stroke Width
                SettingsSection(title: "Stroke Width") {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Slider(
                                value: $viewModel.strokeWidth,
                                in: SettingsViewModel.strokeWidthRange,
                                step: 0.5
                            )
                            .tint(.blue)

                            Text("\(viewModel.strokeWidth, specifier: "%.1f") pt")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 55, alignment: .trailing)
                        }

                        // Visual Preview
                        HStack {
                            Text("Preview")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            RoundedRectangle(cornerRadius: viewModel.strokeWidth / 2)
                                .fill(viewModel.strokeColor)
                                .frame(width: 120, height: max(viewModel.strokeWidth, 2))
                        }
                    }
                }

                // Text Size
                SettingsSection(title: "Text Size") {
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            Slider(
                                value: $viewModel.textSize,
                                in: SettingsViewModel.textSizeRange,
                                step: 1
                            )
                            .tint(.blue)

                            Text("\(Int(viewModel.textSize)) pt")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 55, alignment: .trailing)
                        }

                        // Visual Preview
                        HStack {
                            Text("Preview")
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("Sample Text")
                                .font(.system(size: min(viewModel.textSize, 28)))
                                .foregroundStyle(viewModel.strokeColor)
                        }
                    }
                }
            }
            .padding(24)
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

/// A section container for settings with a title.
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}

/// A single permission row with status and action.
private struct PermissionRow: View {
    let icon: String
    let title: String
    let isGranted: Bool
    let isChecking: Bool
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 30)

            Text(title)
                .font(.body)

            Spacer()

            if isChecking {
                ProgressView()
                    .controlSize(.small)
            } else if isGranted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Granted")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("Grant Access") {
                    onGrant()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 10)
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 26)

            Text(label)
                .font(.body)

            Spacer()

            Button {
                onRecord()
            } label: {
                HStack(spacing: 6) {
                    if isRecording {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text("Press keys...")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(shortcut.displayString)
                            .font(.system(.body, design: .monospaced, weight: .medium))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRecording ? Color.red.opacity(0.1) : Color.primary.opacity(0.05))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isRecording ? Color.red.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            Button {
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset to default")
            .disabled(isRecording)
            .opacity(isRecording ? 0.4 : 1)
        }
        .padding(.vertical, 10)
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
                .frame(width: 30, height: 30)
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(Color.primary, lineWidth: 2.5)
                            .padding(3)
                    }
                }
                .overlay {
                    if color == .white || color == .yellow {
                        Circle()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                    }
                }
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
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
