import AppKit

/// Manages the menu bar status item and its menu.
/// Responsible for setting up the menu bar icon and building the app menu.
@MainActor
final class MenuBarController {
    // MARK: - Properties

    /// The status item displayed in the menu bar
    private var statusItem: NSStatusItem?

    /// Reference to the app delegate for action routing
    private weak var appDelegate: AppDelegate?

    /// Store for recent captures
    private let recentCapturesStore: RecentCapturesStore

    /// The submenu for recent captures
    private var recentCapturesMenu: NSMenu?

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

        statusItem?.menu = buildMenu()
    }

    /// Removes the status item from the menu bar
    func teardown() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: - Menu Construction

    /// Builds the complete menu for the status item
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Capture Full Screen
        let fullScreenItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.full.screen", comment: "Capture Full Screen"),
            action: #selector(AppDelegate.captureFullScreen),
            keyEquivalent: "3"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .shift]
        fullScreenItem.target = appDelegate
        menu.addItem(fullScreenItem)

        // Capture Selection
        let selectionItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.selection", comment: "Capture Selection"),
            action: #selector(AppDelegate.captureSelection),
            keyEquivalent: "4"
        )
        selectionItem.keyEquivalentModifierMask = [.command, .shift]
        selectionItem.target = appDelegate
        menu.addItem(selectionItem)

        // Capture Window
        let windowItem = NSMenuItem(
            title: NSLocalizedString("menu.capture.window", comment: "Capture Window"),
            action: #selector(AppDelegate.captureWindow),
            keyEquivalent: "6"
        )
        windowItem.keyEquivalentModifierMask = [.command, .shift]
        windowItem.target = appDelegate
        menu.addItem(windowItem)

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
        updateRecentCapturesMenu(menu)
        return menu
    }

    /// Updates the recent captures submenu with current captures
    func updateRecentCapturesMenu() {
        guard let menu = recentCapturesMenu else { return }
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

    /// Opens a recent capture file in Finder
    @objc private func openRecentCapture(_ sender: NSMenuItem) {
        guard let item = sender as? RecentCaptureMenuItem else { return }
        let url = item.capture.filePath

        if item.capture.fileExists {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // File no longer exists, remove from recent captures
            recentCapturesStore.remove(capture: item.capture)
            updateRecentCapturesMenu()
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
