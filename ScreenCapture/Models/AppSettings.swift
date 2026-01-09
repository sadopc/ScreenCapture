import Foundation
import SwiftUI
import ServiceManagement

/// User preferences persisted across sessions via UserDefaults.
/// All properties automatically sync to UserDefaults with the `ScreenCapture.` prefix.
@MainActor
@Observable
final class AppSettings {
    // MARK: - Singleton

    /// Shared settings instance
    static let shared = AppSettings()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let prefix = "ScreenCapture."
        static let saveLocation = prefix + "saveLocation"
        static let defaultFormat = prefix + "defaultFormat"
        static let jpegQuality = prefix + "jpegQuality"
        static let fullScreenShortcut = prefix + "fullScreenShortcut"
        static let selectionShortcut = prefix + "selectionShortcut"
        static let windowShortcut = prefix + "windowShortcut"
        static let windowWithShadowShortcut = prefix + "windowWithShadowShortcut"
        static let strokeColor = prefix + "strokeColor"
        static let strokeWidth = prefix + "strokeWidth"
        static let textSize = prefix + "textSize"
        static let rectangleFilled = prefix + "rectangleFilled"
        static let recentCaptures = prefix + "recentCaptures"
        static let autoSaveOnClose = prefix + "autoSaveOnClose"
    }

    // MARK: - Properties

    /// Default save directory
    var saveLocation: URL {
        didSet { save(saveLocation.path, forKey: Keys.saveLocation) }
    }

    /// Default export format (PNG or JPEG)
    var defaultFormat: ExportFormat {
        didSet { save(defaultFormat.rawValue, forKey: Keys.defaultFormat) }
    }

    /// JPEG compression quality (0.0-1.0)
    var jpegQuality: Double {
        didSet { save(jpegQuality, forKey: Keys.jpegQuality) }
    }

    /// Global hotkey for full screen capture
    var fullScreenShortcut: KeyboardShortcut {
        didSet { saveShortcut(fullScreenShortcut, forKey: Keys.fullScreenShortcut) }
    }

    /// Global hotkey for selection capture
    var selectionShortcut: KeyboardShortcut {
        didSet { saveShortcut(selectionShortcut, forKey: Keys.selectionShortcut) }
    }

    /// Global hotkey for window capture
    var windowShortcut: KeyboardShortcut {
        didSet { saveShortcut(windowShortcut, forKey: Keys.windowShortcut) }
    }

    /// Global hotkey for window capture with shadow
    var windowWithShadowShortcut: KeyboardShortcut {
        didSet { saveShortcut(windowWithShadowShortcut, forKey: Keys.windowWithShadowShortcut) }
    }

    /// Default annotation stroke color
    var strokeColor: CodableColor {
        didSet { saveColor(strokeColor, forKey: Keys.strokeColor) }
    }

    /// Default annotation stroke width
    var strokeWidth: CGFloat {
        didSet { save(Double(strokeWidth), forKey: Keys.strokeWidth) }
    }

    /// Default text annotation font size
    var textSize: CGFloat {
        didSet { save(Double(textSize), forKey: Keys.textSize) }
    }

    /// Whether rectangles are filled (solid) by default
    var rectangleFilled: Bool {
        didSet { save(rectangleFilled, forKey: Keys.rectangleFilled) }
    }

    /// Last 5 saved captures
    var recentCaptures: [RecentCapture] {
        didSet { saveRecentCaptures() }
    }

    /// Whether to auto-save screenshots when closing the preview
    var autoSaveOnClose: Bool {
        didSet { save(autoSaveOnClose, forKey: Keys.autoSaveOnClose) }
    }

    /// Whether to launch at login
    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(newValue ? "enable" : "disable") launch at login: \(error)")
            }
        }
    }

    // MARK: - Initialization

    private init() {
        let defaults = UserDefaults.standard

        // Load save location from bookmark first, then path, or use Desktop
        let loadedLocation: URL
        if let bookmarkData = defaults.data(forKey: "SaveLocationBookmark"),
           let url = Self.resolveBookmark(bookmarkData) {
            loadedLocation = url
        } else if let path = defaults.string(forKey: Keys.saveLocation) {
            loadedLocation = URL(fileURLWithPath: path)
        } else {
            loadedLocation = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
        }
        saveLocation = loadedLocation

        // Load format
        if let formatRaw = defaults.string(forKey: Keys.defaultFormat),
           let format = ExportFormat(rawValue: formatRaw) {
            defaultFormat = format
        } else {
            defaultFormat = .png
        }

        // Load JPEG quality
        jpegQuality = defaults.object(forKey: Keys.jpegQuality) as? Double ?? 0.9

        // Load shortcuts
        fullScreenShortcut = Self.loadShortcut(forKey: Keys.fullScreenShortcut)
            ?? KeyboardShortcut.fullScreenDefault
        selectionShortcut = Self.loadShortcut(forKey: Keys.selectionShortcut)
            ?? KeyboardShortcut.selectionDefault
        windowShortcut = Self.loadShortcut(forKey: Keys.windowShortcut)
            ?? KeyboardShortcut.windowDefault
        windowWithShadowShortcut = Self.loadShortcut(forKey: Keys.windowWithShadowShortcut)
            ?? KeyboardShortcut.windowWithShadowDefault

        // Load annotation defaults
        strokeColor = Self.loadColor(forKey: Keys.strokeColor) ?? .red
        strokeWidth = CGFloat(defaults.object(forKey: Keys.strokeWidth) as? Double ?? 2.0)
        textSize = CGFloat(defaults.object(forKey: Keys.textSize) as? Double ?? 14.0)
        rectangleFilled = defaults.object(forKey: Keys.rectangleFilled) as? Bool ?? false

        // Load recent captures
        recentCaptures = Self.loadRecentCaptures()

        // Load auto-save setting (default: true)
        autoSaveOnClose = defaults.object(forKey: Keys.autoSaveOnClose) as? Bool ?? true

        print("ScreenCapture launched - settings loaded from: \(loadedLocation.path)")
    }

    // MARK: - Computed Properties

    /// Default stroke style based on current settings
    var defaultStrokeStyle: StrokeStyle {
        StrokeStyle(color: strokeColor, lineWidth: strokeWidth)
    }

    /// Default text style based on current settings
    var defaultTextStyle: TextStyle {
        TextStyle(color: strokeColor, fontSize: textSize, fontName: ".AppleSystemUIFont")
    }

    // MARK: - Recent Captures Management

    /// Adds a capture to the recent list (maintains max 5, FIFO)
    func addRecentCapture(_ capture: RecentCapture) {
        recentCaptures.insert(capture, at: 0)
        if recentCaptures.count > 5 {
            recentCaptures = Array(recentCaptures.prefix(5))
        }
    }

    /// Clears all recent captures
    func clearRecentCaptures() {
        recentCaptures = []
    }

    // MARK: - Reset

    /// Resets all settings to defaults
    func resetToDefaults() {
        saveLocation = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        defaultFormat = .png
        jpegQuality = 0.9
        fullScreenShortcut = .fullScreenDefault
        selectionShortcut = .selectionDefault
        windowShortcut = .windowDefault
        windowWithShadowShortcut = .windowWithShadowDefault
        strokeColor = .red
        strokeWidth = 2.0
        textSize = 14.0
        rectangleFilled = false
        recentCaptures = []
        autoSaveOnClose = true
    }

    // MARK: - Private Persistence Helpers

    private func save(_ value: Any, forKey key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func saveShortcut(_ shortcut: KeyboardShortcut, forKey key: String) {
        let data: [String: UInt32] = [
            "keyCode": shortcut.keyCode,
            "modifiers": shortcut.modifiers
        ]
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadShortcut(forKey key: String) -> KeyboardShortcut? {
        guard let data = UserDefaults.standard.dictionary(forKey: key) as? [String: UInt32],
              let keyCode = data["keyCode"],
              let modifiers = data["modifiers"] else {
            return nil
        }
        return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func saveColor(_ color: CodableColor, forKey key: String) {
        if let data = try? JSONEncoder().encode(color) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadColor(forKey key: String) -> CodableColor? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CodableColor.self, from: data)
    }

    private func saveRecentCaptures() {
        if let data = try? JSONEncoder().encode(recentCaptures) {
            UserDefaults.standard.set(data, forKey: Keys.recentCaptures)
        }
    }

    private static func loadRecentCaptures() -> [RecentCapture] {
        guard let data = UserDefaults.standard.data(forKey: Keys.recentCaptures) else {
            return []
        }
        return (try? JSONDecoder().decode([RecentCapture].self, from: data)) ?? []
    }

    /// Resolves a security-scoped bookmark to a URL
    private static func resolveBookmark(_ bookmarkData: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Start accessing the security-scoped resource
            if url.startAccessingSecurityScopedResource() {
                // Note: We don't call stopAccessingSecurityScopedResource()
                // because we need ongoing access throughout the app's lifetime
                return url
            }
            return url
        } catch {
            print("Failed to resolve bookmark: \(error)")
            return nil
        }
    }
}

// MARK: - Recent Capture

/// Entry in the recent captures list.
struct RecentCapture: Identifiable, Codable, Sendable {
    /// Unique identifier
    let id: UUID

    /// Location of saved file
    let filePath: URL

    /// When the screenshot was captured
    let captureDate: Date

    /// JPEG thumbnail data (max 10KB, 128px on longest edge)
    let thumbnailData: Data?

    init(id: UUID = UUID(), filePath: URL, captureDate: Date = Date(), thumbnailData: Data? = nil) {
        self.id = id
        self.filePath = filePath
        self.captureDate = captureDate
        self.thumbnailData = thumbnailData
    }

    /// The filename without path
    var filename: String {
        filePath.lastPathComponent
    }

    /// Whether the file still exists on disk
    var fileExists: Bool {
        FileManager.default.fileExists(atPath: filePath.path)
    }
}
