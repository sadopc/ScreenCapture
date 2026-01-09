import Foundation
import SwiftUI
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// ViewModel for the Settings view.
/// Manages user preferences and provides bindings for the settings UI.
@MainActor
@Observable
final class SettingsViewModel {
    // MARK: - Properties

    /// Reference to shared app settings
    private let settings: AppSettings

    /// Reference to app delegate for hotkey re-registration
    private weak var appDelegate: AppDelegate?

    /// Whether a shortcut is currently being recorded
    var isRecordingFullScreenShortcut = false
    var isRecordingSelectionShortcut = false
    var isRecordingWindowShortcut = false
    var isRecordingWindowWithShadowShortcut = false

    /// Temporary storage for shortcut recording
    var recordedShortcut: KeyboardShortcut?

    /// Error message to display
    var errorMessage: String?

    /// Whether to show error alert
    var showErrorAlert = false

    /// Screen recording permission status
    var hasScreenRecordingPermission: Bool = false

    /// Folder access permission status
    var hasFolderAccessPermission: Bool = false

    /// Whether permission check is in progress
    var isCheckingPermissions: Bool = false

    // MARK: - Computed Properties (Bindings to AppSettings)

    /// Save location URL
    var saveLocation: URL {
        get { settings.saveLocation }
        set { settings.saveLocation = newValue }
    }

    /// Save location display path
    var saveLocationPath: String {
        saveLocation.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    /// Default export format
    var defaultFormat: ExportFormat {
        get { settings.defaultFormat }
        set { settings.defaultFormat = newValue }
    }

    /// JPEG quality (0.0-1.0)
    var jpegQuality: Double {
        get { settings.jpegQuality }
        set { settings.jpegQuality = newValue }
    }

    /// JPEG quality as percentage (0-100)
    var jpegQualityPercentage: Double {
        get { jpegQuality * 100 }
        set { jpegQuality = newValue / 100 }
    }

    /// Launch at login
    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set { settings.launchAtLogin = newValue }
    }

    /// Auto-save on close
    var autoSaveOnClose: Bool {
        get { settings.autoSaveOnClose }
        set { settings.autoSaveOnClose = newValue }
    }

    /// Full screen capture shortcut
    var fullScreenShortcut: KeyboardShortcut {
        get { settings.fullScreenShortcut }
        set {
            settings.fullScreenShortcut = newValue
            appDelegate?.updateHotkeys()
        }
    }

    /// Selection capture shortcut
    var selectionShortcut: KeyboardShortcut {
        get { settings.selectionShortcut }
        set {
            settings.selectionShortcut = newValue
            appDelegate?.updateHotkeys()
        }
    }

    /// Window capture shortcut
    var windowShortcut: KeyboardShortcut {
        get { settings.windowShortcut }
        set {
            settings.windowShortcut = newValue
            appDelegate?.updateHotkeys()
        }
    }

    /// Window with shadow capture shortcut
    var windowWithShadowShortcut: KeyboardShortcut {
        get { settings.windowWithShadowShortcut }
        set {
            settings.windowWithShadowShortcut = newValue
            appDelegate?.updateHotkeys()
        }
    }

    /// Annotation stroke color
    var strokeColor: Color {
        get { settings.strokeColor.color }
        set { settings.strokeColor = CodableColor(newValue) }
    }

    /// Annotation stroke width
    var strokeWidth: CGFloat {
        get { settings.strokeWidth }
        set { settings.strokeWidth = newValue }
    }

    /// Text annotation font size
    var textSize: CGFloat {
        get { settings.textSize }
        set { settings.textSize = newValue }
    }

    // MARK: - Validation Ranges

    /// Valid range for stroke width
    static let strokeWidthRange: ClosedRange<CGFloat> = 1.0...20.0

    /// Valid range for text size
    static let textSizeRange: ClosedRange<CGFloat> = 8.0...72.0

    /// Valid range for JPEG quality
    static let jpegQualityRange: ClosedRange<Double> = 0.1...1.0

    // MARK: - Initialization

    init(settings: AppSettings = .shared, appDelegate: AppDelegate? = nil) {
        self.settings = settings
        self.appDelegate = appDelegate
    }

    // MARK: - Permission Checking

    /// Checks all required permissions and updates status
    func checkPermissions() {
        isCheckingPermissions = true

        // Check screen recording permission using CGPreflightScreenCaptureAccess
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()

        // Check folder access permission by testing if we can write to the save location
        hasFolderAccessPermission = checkFolderAccess(to: saveLocation)

        isCheckingPermissions = false
    }

    /// Checks if we have write access to the specified folder
    private func checkFolderAccess(to url: URL) -> Bool {
        let fileManager = FileManager.default

        // Check if directory exists and is writable
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }

        return fileManager.isWritableFile(atPath: url.path)
    }

    /// Requests screen recording permission or opens System Settings
    func requestScreenRecordingPermission() {
        // First try to request permission (this triggers the system prompt if not asked before)
        let hasAccess = CGRequestScreenCaptureAccess()

        if !hasAccess {
            // If no access, open System Settings to the Screen Recording pane
            openScreenRecordingSettings()
        }

        // Recheck permissions after a short delay
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            checkPermissions()
        }
    }

    /// Requests folder access by showing a folder picker
    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Grant Access"
        panel.message = "Select the folder where you want to save screenshots"
        panel.directoryURL = saveLocation

        if panel.runModal() == .OK, let url = panel.url {
            // Save the security-scoped bookmark for persistent access
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "SaveLocationBookmark")
                saveLocation = url
            } catch {
                // If bookmark fails, just save the URL
                saveLocation = url
            }
        }

        // Recheck permissions
        checkPermissions()
    }

    /// Opens System Settings to the Screen Recording privacy pane
    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Actions

    /// Shows folder selection panel to choose save location
    func selectSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose the default location for saving screenshots"
        panel.directoryURL = saveLocation

        if panel.runModal() == .OK, let url = panel.url {
            // Save the security-scoped bookmark for persistent access
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "SaveLocationBookmark")
            } catch {
                // Ignore bookmark errors
            }
            saveLocation = url
            checkPermissions()
        }
    }

    /// Reveals the save location in Finder
    func revealSaveLocation() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: saveLocation.path)
    }

    /// Starts recording a keyboard shortcut for full screen capture
    func startRecordingFullScreenShortcut() {
        isRecordingFullScreenShortcut = true
        isRecordingSelectionShortcut = false
        isRecordingWindowShortcut = false
        isRecordingWindowWithShadowShortcut = false
        recordedShortcut = nil
    }

    /// Starts recording a keyboard shortcut for selection capture
    func startRecordingSelectionShortcut() {
        isRecordingFullScreenShortcut = false
        isRecordingSelectionShortcut = true
        isRecordingWindowShortcut = false
        isRecordingWindowWithShadowShortcut = false
        recordedShortcut = nil
    }

    /// Starts recording a keyboard shortcut for window capture
    func startRecordingWindowShortcut() {
        isRecordingFullScreenShortcut = false
        isRecordingSelectionShortcut = false
        isRecordingWindowShortcut = true
        isRecordingWindowWithShadowShortcut = false
        recordedShortcut = nil
    }

    /// Starts recording a keyboard shortcut for window with shadow capture
    func startRecordingWindowWithShadowShortcut() {
        isRecordingFullScreenShortcut = false
        isRecordingSelectionShortcut = false
        isRecordingWindowShortcut = false
        isRecordingWindowWithShadowShortcut = true
        recordedShortcut = nil
    }

    /// Cancels shortcut recording
    func cancelRecording() {
        isRecordingFullScreenShortcut = false
        isRecordingSelectionShortcut = false
        isRecordingWindowShortcut = false
        isRecordingWindowWithShadowShortcut = false
        recordedShortcut = nil
    }

    /// Handles a key event during shortcut recording
    /// - Parameter event: The key event
    /// - Returns: Whether the event was handled
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let isRecording = isRecordingFullScreenShortcut || isRecordingSelectionShortcut ||
                          isRecordingWindowShortcut || isRecordingWindowWithShadowShortcut
        guard isRecording else {
            return false
        }

        // Escape cancels recording
        if event.keyCode == UInt16(kVK_Escape) {
            cancelRecording()
            return true
        }

        // Create shortcut from event
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifierFlags: event.modifierFlags.intersection([.command, .shift, .option, .control])
        )

        // Validate shortcut
        guard shortcut.isValid else {
            showError("Shortcuts must include Command, Control, or Option")
            return true
        }

        // Check for conflicts with other shortcuts
        let allShortcuts = [
            ("Full Screen Capture", fullScreenShortcut, isRecordingFullScreenShortcut),
            ("Selection Capture", selectionShortcut, isRecordingSelectionShortcut),
            ("Window Capture", windowShortcut, isRecordingWindowShortcut),
            ("Window with Shadow", windowWithShadowShortcut, isRecordingWindowWithShadowShortcut)
        ]

        for (name, existingShortcut, isCurrentlyRecording) in allShortcuts {
            if !isCurrentlyRecording && shortcut == existingShortcut {
                showError("This shortcut is already used for \(name)")
                return true
            }
        }

        // Apply the shortcut
        if isRecordingFullScreenShortcut {
            fullScreenShortcut = shortcut
        } else if isRecordingSelectionShortcut {
            selectionShortcut = shortcut
        } else if isRecordingWindowShortcut {
            windowShortcut = shortcut
        } else if isRecordingWindowWithShadowShortcut {
            windowWithShadowShortcut = shortcut
        }

        // End recording
        cancelRecording()
        return true
    }

    /// Resets a shortcut to its default
    func resetFullScreenShortcut() {
        fullScreenShortcut = .fullScreenDefault
    }

    /// Resets selection shortcut to default
    func resetSelectionShortcut() {
        selectionShortcut = .selectionDefault
    }

    /// Resets window shortcut to default
    func resetWindowShortcut() {
        windowShortcut = .windowDefault
    }

    /// Resets window with shadow shortcut to default
    func resetWindowWithShadowShortcut() {
        windowWithShadowShortcut = .windowWithShadowDefault
    }

    /// Resets all settings to defaults
    func resetAllToDefaults() {
        settings.resetToDefaults()
        appDelegate?.updateHotkeys()
    }

    // MARK: - Private Helpers

    /// Shows an error message
    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

// MARK: - Preset Colors

extension SettingsViewModel {
    /// Preset colors for the color picker
    static let presetColors: [Color] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .pink,
        .white,
        .black
    ]
}
