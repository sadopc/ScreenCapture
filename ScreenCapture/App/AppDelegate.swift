import AppKit
import ScreenCaptureKit

/// Application delegate responsible for menu bar setup, hotkey registration, and app lifecycle.
/// Runs on the main actor to ensure thread-safe UI operations.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Properties

    /// Menu bar controller for status item management
    private var menuBarController: MenuBarController?

    /// Store for recent captures
    private var recentCapturesStore: RecentCapturesStore?

    /// Registered hotkey for full screen capture
    private var fullScreenHotkeyRegistration: HotkeyManager.Registration?

    /// Registered hotkey for selection capture
    private var selectionHotkeyRegistration: HotkeyManager.Registration?

    /// Registered hotkey for window capture
    private var windowHotkeyRegistration: HotkeyManager.Registration?

    /// Shared app settings
    private let settings = AppSettings.shared

    /// Display selector for multi-monitor support
    private let displaySelector = DisplaySelector()

    /// Whether a capture is currently in progress (prevents overlapping captures)
    private var isCaptureInProgress = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure we're a menu bar only app (no dock icon)
        NSApp.setActivationPolicy(.accessory)

        // Initialize recent captures store
        recentCapturesStore = RecentCapturesStore(settings: settings)

        // Set up menu bar
        menuBarController = MenuBarController(
            appDelegate: self,
            recentCapturesStore: recentCapturesStore!
        )
        menuBarController?.setup()

        // Register global hotkeys
        Task {
            await registerHotkeys()
        }

        // Check for screen recording permission on first launch
        Task {
            await checkAndRequestScreenRecordingPermission()
        }

        #if DEBUG
        print("ScreenCapture launched - settings loaded from: \(settings.saveLocation.path)")
        #endif
    }

    /// Checks for screen recording permission and shows an explanatory prompt if needed.
    private func checkAndRequestScreenRecordingPermission() async {
        // Check if we already have permission
        let hasPermission = await CaptureManager.shared.hasPermission

        if !hasPermission {
            // Show an explanatory alert before triggering the system prompt
            await MainActor.run {
                showPermissionExplanationAlert()
            }
        }
    }

    /// Shows an alert explaining why screen recording permission is needed.
    private func showPermissionExplanationAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("permission.prompt.title", comment: "Screen Recording Permission Required")
        alert.informativeText = NSLocalizedString("permission.prompt.message", comment: "")
        alert.addButton(withTitle: NSLocalizedString("permission.prompt.continue", comment: "Continue"))
        alert.addButton(withTitle: NSLocalizedString("permission.prompt.later", comment: "Later"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Trigger the system permission prompt by attempting a capture
            Task {
                _ = await CaptureManager.shared.requestPermission()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Unregister hotkeys
        Task {
            await unregisterHotkeys()
        }

        // Remove menu bar item
        menuBarController?.teardown()

        #if DEBUG
        print("ScreenCapture terminating")
        #endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // For menu bar apps, we don't need to do anything special on reopen
        // The menu bar icon is always visible
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        // Enable secure state restoration
        return true
    }

    // MARK: - Hotkey Management

    /// Registers global hotkeys for capture actions
    private func registerHotkeys() async {
        let hotkeyManager = HotkeyManager.shared

        // Register full screen capture hotkey
        do {
            fullScreenHotkeyRegistration = try await hotkeyManager.register(
                shortcut: settings.fullScreenShortcut
            ) { [weak self] in
                Task { @MainActor in
                    self?.captureFullScreen()
                }
            }
            #if DEBUG
            print("Registered full screen hotkey: \(settings.fullScreenShortcut.displayString)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to register full screen hotkey: \(error)")
            #endif
        }

        // Register selection capture hotkey
        do {
            selectionHotkeyRegistration = try await hotkeyManager.register(
                shortcut: settings.selectionShortcut
            ) { [weak self] in
                Task { @MainActor in
                    self?.captureSelection()
                }
            }
            #if DEBUG
            print("Registered selection hotkey: \(settings.selectionShortcut.displayString)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to register selection hotkey: \(error)")
            #endif
        }

        // Register window capture hotkey
        do {
            windowHotkeyRegistration = try await hotkeyManager.register(
                shortcut: settings.windowShortcut
            ) { [weak self] in
                Task { @MainActor in
                    self?.captureWindow()
                }
            }
            #if DEBUG
            print("Registered window hotkey: \(settings.windowShortcut.displayString)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to register window hotkey: \(error)")
            #endif
        }
    }

    /// Unregisters all global hotkeys
    private func unregisterHotkeys() async {
        let hotkeyManager = HotkeyManager.shared

        if let registration = fullScreenHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            fullScreenHotkeyRegistration = nil
        }

        if let registration = selectionHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            selectionHotkeyRegistration = nil
        }

        if let registration = windowHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            windowHotkeyRegistration = nil
        }
    }

    /// Re-registers hotkeys after settings change
    func updateHotkeys() {
        Task {
            await unregisterHotkeys()
            await registerHotkeys()
        }
    }

    // MARK: - Capture Actions

    /// Triggers a full screen capture
    @objc func captureFullScreen() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else {
            #if DEBUG
            print("Capture already in progress, ignoring request")
            #endif
            return
        }

        #if DEBUG
        print("Full screen capture triggered via hotkey or menu")
        #endif

        isCaptureInProgress = true

        Task {
            defer { isCaptureInProgress = false }

            do {
                // Get available displays
                let displays = try await CaptureManager.shared.availableDisplays()

                // Select display (shows menu if multiple)
                guard let selectedDisplay = await displaySelector.selectDisplay(from: displays) else {
                    #if DEBUG
                    print("Display selection cancelled")
                    #endif
                    return
                }

                #if DEBUG
                print("Capturing display: \(selectedDisplay.name)")
                #endif

                // Perform capture
                let screenshot = try await CaptureManager.shared.captureFullScreen(display: selectedDisplay)

                #if DEBUG
                print("Capture successful: \(screenshot.formattedDimensions)")
                #endif

                // Show preview window
                PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
                    // Add to recent captures when saved
                    self?.addRecentCapture(filePath: savedURL, image: screenshot.image)
                }

            } catch let error as ScreenCaptureError {
                showCaptureError(error)
            } catch {
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Triggers a selection capture
    @objc func captureSelection() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else {
            #if DEBUG
            print("Capture already in progress, ignoring request")
            #endif
            return
        }

        #if DEBUG
        print("Selection capture triggered via hotkey or menu")
        #endif

        isCaptureInProgress = true

        Task {
            do {
                // Present the selection overlay on all displays
                let overlayController = SelectionOverlayController.shared

                // Set up callbacks before presenting
                overlayController.onSelectionComplete = { [weak self] rect, display in
                    Task { @MainActor in
                        await self?.handleSelectionComplete(rect: rect, display: display)
                    }
                }

                overlayController.onSelectionCancel = { [weak self] in
                    Task { @MainActor in
                        self?.handleSelectionCancel()
                    }
                }

                try await overlayController.presentOverlay()

            } catch {
                isCaptureInProgress = false
                #if DEBUG
                print("Failed to present selection overlay: \(error)")
                #endif
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Triggers a window capture
    @objc func captureWindow() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else {
            #if DEBUG
            print("Capture already in progress, ignoring request")
            #endif
            return
        }

        #if DEBUG
        print("Window capture triggered via hotkey or menu")
        #endif

        isCaptureInProgress = true

        Task {
            do {
                // Present the window selector
                let selectorController = WindowSelectorController.shared

                // Set up callbacks before presenting
                selectorController.onWindowSelected = { [weak self] windowID in
                    Task { @MainActor in
                        await self?.handleWindowSelected(windowID)
                    }
                }

                selectorController.onCancel = { [weak self] in
                    Task { @MainActor in
                        self?.handleWindowSelectionCancel()
                    }
                }

                try await selectorController.presentSelector()

            } catch {
                isCaptureInProgress = false
                #if DEBUG
                print("Failed to present window selector: \(error)")
                #endif
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Handles successful window selection
    private func handleWindowSelected(_ windowID: CGWindowID) async {
        defer { isCaptureInProgress = false }

        do {
            #if DEBUG
            print("Window selected: ID \(windowID)")
            #endif

            // Capture the selected window by ID
            let screenshot = try await WindowCaptureService.shared.captureWindowByID(windowID)

            #if DEBUG
            print("Window capture successful: \(screenshot.formattedDimensions)")
            #endif

            // Show preview window
            PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
                // Add to recent captures when saved
                self?.addRecentCapture(filePath: savedURL, image: screenshot.image)
            }

        } catch let error as ScreenCaptureError {
            showCaptureError(error)
        } catch {
            showCaptureError(.captureFailure(underlying: error))
        }
    }

    /// Handles window selection cancellation
    private func handleWindowSelectionCancel() {
        isCaptureInProgress = false
        #if DEBUG
        print("Window selection cancelled by user")
        #endif
    }

    /// Handles successful selection completion
    private func handleSelectionComplete(rect: CGRect, display: DisplayInfo) async {
        defer { isCaptureInProgress = false }

        do {
            #if DEBUG
            print("Selection complete: \(Int(rect.width))×\(Int(rect.height)) on \(display.name)")
            #endif

            // Capture the selected region
            let screenshot = try await CaptureManager.shared.captureRegion(rect, from: display)

            #if DEBUG
            print("Region capture successful: \(screenshot.formattedDimensions)")
            #endif

            // Show preview window
            PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
                // Add to recent captures when saved
                self?.addRecentCapture(filePath: savedURL, image: screenshot.image)
            }

        } catch let error as ScreenCaptureError {
            showCaptureError(error)
        } catch {
            showCaptureError(.captureFailure(underlying: error))
        }
    }

    /// Handles selection cancellation
    private func handleSelectionCancel() {
        isCaptureInProgress = false
        #if DEBUG
        print("Selection cancelled by user")
        #endif
    }

    /// Opens the settings window
    @objc func openSettings() {
        #if DEBUG
        print("Opening settings window")
        #endif

        SettingsWindowController.shared.showSettings(appDelegate: self)
    }

    // MARK: - Error Handling

    /// Shows an error alert for capture failures
    private func showCaptureError(_ error: ScreenCaptureError) {
        #if DEBUG
        print("Capture error: \(error)")
        #endif

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = error.errorDescription ?? NSLocalizedString("error.capture.failed", comment: "")
        alert.informativeText = error.recoverySuggestion ?? ""

        switch error {
        case .permissionDenied:
            alert.addButton(withTitle: NSLocalizedString("error.permission.open.settings", comment: "Open System Settings"))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open System Settings > Privacy > Screen Recording
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }

        case .displayDisconnected:
            // Offer to retry capture on a different display
            alert.addButton(withTitle: NSLocalizedString("error.retry.capture", comment: "Retry"))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Retry the capture on the remaining displays
                captureFullScreen()
            }

        case .diskFull, .invalidSaveLocation:
            // Offer to open settings to change save location
            alert.addButton(withTitle: NSLocalizedString("menu.settings", comment: "Settings..."))
            alert.addButton(withTitle: NSLocalizedString("error.dismiss", comment: "Dismiss"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openSettings()
            }

        default:
            alert.addButton(withTitle: NSLocalizedString("error.ok", comment: "OK"))
            alert.runModal()
        }
    }

    // MARK: - Recent Captures

    /// Adds a capture to recent captures store
    func addRecentCapture(filePath: URL, image: CGImage) {
        recentCapturesStore?.add(filePath: filePath, image: image)
        menuBarController?.updateRecentCapturesMenu()
    }
}
