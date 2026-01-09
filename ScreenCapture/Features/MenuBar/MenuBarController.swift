import AppKit
import Combine

/// Manages the menu bar status item and its menu.
/// Responsible for setting up the menu bar icon and building the app menu.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    // MARK: - Properties

    /// The status item displayed in the menu bar
    private var statusItem: NSStatusItem?

    /// Reference to the app delegate for action routing
    private weak var appDelegate: AppDelegate?

    /// Store for recent captures
    private let recentCapturesStore: RecentCapturesStore

    /// The main menu
    private var menu: NSMenu?

    /// The submenu for recent captures
    private var recentCapturesMenu: NSMenu?

    /// Menu items that need shortcut updates
    private var fullScreenMenuItem: NSMenuItem?
    private var selectionMenuItem: NSMenuItem?
    private var windowMenuItem: NSMenuItem?
    private var windowWithShadowMenuItem: NSMenuItem?

    /// Settings observation
    private var settingsObservation: Any?

    // MARK: - Initialization

    init(appDelegate: AppDelegate, recentCapturesStore: RecentCapturesStore) {
        self.appDelegate = appDelegate
        self.recentCapturesStore = recentCapturesStore
    }

    // MARK: - Setup

    /// Sets up the menu bar status item with icon and menu
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "ScreenCapture")
            button.image?.isTemplate = true
        }

        menu = buildMenu()
        statusItem?.menu = menu

        // Observe settings changes to update shortcuts
        observeSettingsChanges()
    }

    /// Removes the status item from the menu bar
    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        settingsObservation = nil
    }

    // MARK: - Settings Observation

    private func observeSettingsChanges() {
        // Use a timer-based approach since @Observable doesn't work well with NSMenu
        // Check every 0.5 seconds for changes
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateShortcutsInMenu()
            }
        }
    }

    /// Updates shortcut display in menu items
    private func updateShortcutsInMenu() {
        let settings = AppSettings.shared

        // Update Full Screen
        if let item = fullScreenMenuItem {
            item.keyEquivalent = settings.fullScreenShortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = settings.fullScreenShortcut.menuModifierMask
        }

        // Update Selection
        if let item = selectionMenuItem {
            item.keyEquivalent = settings.selectionShortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = settings.selectionShortcut.menuModifierMask
        }

        // Update Window
        if let item = windowMenuItem {
            item.keyEquivalent = settings.windowShortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = settings.windowShortcut.menuModifierMask
        }

        // Update Window with Shadow
        if let item = windowWithShadowMenuItem {
            item.keyEquivalent = settings.windowWithShadowShortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = settings.windowWithShadowShortcut.menuModifierMask
        }
    }

    // MARK: - Menu Construction

    /// Builds the complete menu for the status item
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.minimumWidth = 250  // Ensure all options are visible

        let settings = AppSettings.shared

        // Capture Full Screen
        let fullScreenItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.full.screen", comment: "Capture Full Screen"),
            action: #selector(AppDelegate.captureFullScreen),
            keyEquivalent: settings.fullScreenShortcut.menuKeyEquivalent
        )
        fullScreenItem.keyEquivalentModifierMask = settings.fullScreenShortcut.menuModifierMask
        fullScreenItem.target = appDelegate
        menu.addItem(fullScreenItem)
        self.fullScreenMenuItem = fullScreenItem
        NSLog("[MenuBar] Full screen menu item: keyEquiv=%@, modifiers=%lu, target=%@",
              fullScreenItem.keyEquivalent,
              UInt(fullScreenItem.keyEquivalentModifierMask.rawValue),
              String(describing: fullScreenItem.target))

        // Capture Selection
        let selectionItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.selection", comment: "Capture Selection"),
            action: #selector(AppDelegate.captureSelection),
            keyEquivalent: settings.selectionShortcut.menuKeyEquivalent
        )
        selectionItem.keyEquivalentModifierMask = settings.selectionShortcut.menuModifierMask
        selectionItem.target = appDelegate
        menu.addItem(selectionItem)
        self.selectionMenuItem = selectionItem

        // Capture Window
        let windowItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.window", comment: "Capture Window"),
            action: #selector(AppDelegate.captureWindow),
            keyEquivalent: settings.windowShortcut.menuKeyEquivalent
        )
        windowItem.keyEquivalentModifierMask = settings.windowShortcut.menuModifierMask
        windowItem.target = appDelegate
        menu.addItem(windowItem)
        self.windowMenuItem = windowItem

        // Capture Window with Shadow
        let windowShadowItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.window.shadow", comment: "Capture Window with Shadow"),
            action: #selector(AppDelegate.captureWindowWithShadow),
            keyEquivalent: settings.windowWithShadowShortcut.menuKeyEquivalent
        )
        windowShadowItem.keyEquivalentModifierMask = settings.windowWithShadowShortcut.menuModifierMask
        windowShadowItem.target = appDelegate
        menu.addItem(windowShadowItem)
        self.windowWithShadowMenuItem = windowShadowItem

        menu.addItem(NSMenuItem.separator())

        // Recent Captures submenu
        let recentItem = NSMenuItem(
            title: NSLocalizedString("menu.recent.captures", comment: "Recent Captures"),
            action: nil,
            keyEquivalent: ""
        )
        recentCapturesMenu = buildRecentCapturesMenu()
        recentItem.submenu = recentCapturesMenu
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: NSLocalizedString("menu.settings", comment: "Settings..."),
            action: #selector(AppDelegate.openSettings),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = appDelegate
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: "Quit ScreenCapture"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        return menu
    }

    /// Builds the recent captures submenu
    private func buildRecentCapturesMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self // Reload captures when menu opens
        updateRecentCapturesMenu(menu)
        return menu
    }

    // MARK: - NSMenuDelegate

    /// Called when the menu is about to open - reload recent captures
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            self.recentCapturesStore.reload()
            if let recentMenu = self.recentCapturesMenu {
                self.updateRecentCapturesMenu(recentMenu)
            }
        }
    }

    /// Updates the recent captures submenu with current captures
    func updateRecentCapturesMenu() {
        guard let menu = recentCapturesMenu else { return }
        recentCapturesStore.reload() // Reload from UserDefaults before updating
        updateRecentCapturesMenu(menu)
    }

    /// Updates a given menu with recent captures
    private func updateRecentCapturesMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let captures = recentCapturesStore.captures

        if captures.isEmpty {
            let emptyItem = NSMenuItem(
                title: NSLocalizedString("menu.recent.captures.empty", comment: "No Recent Captures"),
                action: nil,
                keyEquivalent: ""
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for capture in captures {
                let item = RecentCaptureMenuItem(capture: capture)
                item.action = #selector(openRecentCapture(_:))
                item.target = self
                menu.addItem(item)
            }

            menu.addItem(NSMenuItem.separator())

            let clearItem = NSMenuItem(
                title: NSLocalizedString("menu.recent.captures.clear", comment: "Clear Recent"),
                action: #selector(clearRecentCaptures),
                keyEquivalent: ""
            )
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }

    // MARK: - Actions

    /// Opens a recent capture in the editor for viewing/editing
    @objc private func openRecentCapture(_ sender: NSMenuItem) {
        guard let item = sender as? RecentCaptureMenuItem else { return }
        let capture = item.capture

        guard capture.fileExists else {
            // File no longer exists, remove from recent captures
            recentCapturesStore.remove(capture: capture)
            updateRecentCapturesMenu()
            return
        }

        // Load image from file
        guard let nsImage = NSImage(contentsOf: capture.filePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return
        }

        // Create screenshot and open in editor
        let screenshot = Screenshot(
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

        PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
            self?.appDelegate?.addRecentCapture(filePath: savedURL, image: cgImage)
        }
    }

    /// Clears all recent captures
    @objc private func clearRecentCaptures() {
        recentCapturesStore.clear()
        updateRecentCapturesMenu()
    }
}

// MARK: - Recent Capture Menu Item

/// Custom menu item that holds a reference to a RecentCapture
private final class RecentCaptureMenuItem: NSMenuItem {
    let capture: RecentCapture

    init(capture: RecentCapture) {
        self.capture = capture
        super.init(title: capture.filename, action: nil, keyEquivalent: "")

        // Set thumbnail image if available
        if let thumbnailData = capture.thumbnailData,
           let image = NSImage(data: thumbnailData) {
            image.size = NSSize(width: 32, height: 32)
            self.image = image
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
