import AppKit
import ScreenCaptureKit
import AudioToolbox

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

    /// Registered hotkey for window capture with shadow
    private var windowWithShadowHotkeyRegistration: HotkeyManager.Registration?

    /// Shared app settings
    private let settings = AppSettings.shared

    /// Display selector for multi-monitor support
    private let displaySelector = DisplaySelector()

    /// Whether a capture is currently in progress (prevents overlapping captures)
    private var isCaptureInProgress = false

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[ScreenCapture] Application did finish launching")

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

        NSLog("[ScreenCapture] Menu bar set up, registering hotkeys...")

        // Register global hotkeys
        Task {
            await registerHotkeys()
        }

        // Check for screen recording permission on first launch
        Task {
            await checkAndRequestScreenRecordingPermission()
        }

        NSLog("[ScreenCapture] Settings save location: %@", settings.saveLocation.path)
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

        NSLog("[ScreenCapture] Registering hotkeys...")
        NSLog("[ScreenCapture] Full screen shortcut: %@ (keyCode: %u, modifiers: %u)", settings.fullScreenShortcut.displayString, settings.fullScreenShortcut.keyCode, settings.fullScreenShortcut.modifiers)

        // Register full screen capture hotkey
        do {
            fullScreenHotkeyRegistration = try await hotkeyManager.register(
                shortcut: settings.fullScreenShortcut
            ) { [weak self] in
                Task { @MainActor in
                    self?.captureFullScreen()
                }
            }
            NSLog("[ScreenCapture] ✓ Registered full screen hotkey: %@", settings.fullScreenShortcut.displayString)
        } catch {
            NSLog("[ScreenCapture] ✗ Failed to register full screen hotkey: %@", "\(error)")
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
            NSLog("[ScreenCapture] ✓ Registered selection hotkey: %@", settings.selectionShortcut.displayString)
        } catch {
            NSLog("[ScreenCapture] ✗ Failed to register selection hotkey: %@", "\(error)")
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
            NSLog("[ScreenCapture] ✓ Registered window hotkey: %@", settings.windowShortcut.displayString)
        } catch {
            NSLog("[ScreenCapture] ✗ Failed to register window hotkey: %@", "\(error)")
        }

        // Register window with shadow capture hotkey
        do {
            windowWithShadowHotkeyRegistration = try await hotkeyManager.register(
                shortcut: settings.windowWithShadowShortcut
            ) { [weak self] in
                Task { @MainActor in
                    self?.captureWindowWithShadow()
                }
            }
            NSLog("[ScreenCapture] ✓ Registered window with shadow hotkey: %@", settings.windowWithShadowShortcut.displayString)
        } catch {
            NSLog("[ScreenCapture] ✗ Failed to register window with shadow hotkey: %@", "\(error)")
        }

        NSLog("[ScreenCapture] Hotkey registration complete")
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

        if let registration = windowWithShadowHotkeyRegistration {
            await hotkeyManager.unregister(registration)
            windowWithShadowHotkeyRegistration = nil
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
            NSLog("[ScreenCapture] Capture already in progress")
            return
        }

        NSLog("[ScreenCapture] Starting full screen capture")
        isCaptureInProgress = true

        Task {
            defer {
                isCaptureInProgress = false
                NSLog("[ScreenCapture] Capture task finished")
            }

            do {
                // Get available displays
                NSLog("[ScreenCapture] Getting available displays...")
                let displays = try await CaptureManager.shared.availableDisplays()
                NSLog("[ScreenCapture] Found %d displays", displays.count)

                // Select display (shows menu if multiple)
                NSLog("[ScreenCapture] Showing display selector...")
                guard let selectedDisplay = await displaySelector.selectDisplay(from: displays) else {
                    NSLog("[ScreenCapture] Display selection cancelled")
                    return
                }
                NSLog("[ScreenCapture] Selected display: %@", selectedDisplay.name)

                // Perform capture
                NSLog("[ScreenCapture] Capturing display...")
                let screenshot: Screenshot
                do {
                    screenshot = try await CaptureManager.shared.captureFullScreen(display: selectedDisplay)
                } catch {
                    NSLog("[ScreenCapture] CAPTURE FAILED: %@", "\(error)")
                    throw error
                }
                NSLog("[ScreenCapture] Capture successful: %@", screenshot.formattedDimensions)

                // Play screenshot sound
                playScreenshotSound()

                // Show preview window
                NSLog("[ScreenCapture] Showing preview window...")
                await MainActor.run {
                    PreviewWindowController.shared.showPreview(for: screenshot) { [weak self] savedURL in
                        // Add to recent captures when saved
                        self?.addRecentCapture(filePath: savedURL, image: screenshot.image)
                    }
                }
                NSLog("[ScreenCapture] Preview window shown")

            } catch let error as ScreenCaptureError {
                NSLog("[ScreenCapture] ScreenCaptureError: %@", "\(error)")
                showCaptureError(error)
            } catch {
                NSLog("[ScreenCapture] Error: %@", "\(error)")
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Triggers a selection capture
    @objc func captureSelection() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else { return }

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
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Triggers a window capture
    @objc func captureWindow() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else { return }

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
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Triggers a window capture with shadow
    @objc func captureWindowWithShadow() {
        // Prevent overlapping captures
        guard !isCaptureInProgress else { return }

        isCaptureInProgress = true

        Task {
            do {
                // Present the window selector
                let selectorController = WindowSelectorController.shared

                // Set up callbacks before presenting
                selectorController.onWindowSelected = { [weak self] windowID in
                    Task { @MainActor in
                        await self?.handleWindowSelectedWithShadow(windowID)
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
                showCaptureError(.captureFailure(underlying: error))
            }
        }
    }

    /// Handles successful window selection
    private func handleWindowSelected(_ windowID: CGWindowID) async {
        defer { isCaptureInProgress = false }

        do {
            // Capture the selected window by ID
            let screenshot = try await WindowCaptureService.shared.captureWindowByID(windowID)

            // Play screenshot sound
            playScreenshotSound()

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

    /// Handles successful window selection with shadow
    private func handleWindowSelectedWithShadow(_ windowID: CGWindowID) async {
        defer { isCaptureInProgress = false }

        do {
            // Capture the selected window by ID with shadow
            let screenshot = try await WindowCaptureService.shared.captureWindowByID(windowID, includeShadow: true)

            // Play screenshot sound
            playScreenshotSound()

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
    }

    /// Handles successful selection completion
    private func handleSelectionComplete(rect: CGRect, display: DisplayInfo) async {
        defer { isCaptureInProgress = false }

        do {
            // Capture the selected region
            let screenshot = try await CaptureManager.shared.captureRegion(rect, from: display)

            // Play screenshot sound
            playScreenshotSound()

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
    }

    /// Opens the settings window
    @objc func openSettings() {
        SettingsWindowController.shared.showSettings(appDelegate: self)
    }

    // MARK: - Error Handling

    /// Shows an error alert for capture failures
    private func showCaptureError(_ error: ScreenCaptureError) {
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

    // MARK: - Sound

    /// Plays the macOS screenshot sound
    private func playScreenshotSound() {
        // Use the system screenshot sound (same as Cmd+Shift+3)
        if let soundURL = Bundle.main.url(forResource: "Grab", withExtension: "aiff") {
            // Try bundled sound first
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else if let systemSoundPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif" as String?,
                  FileManager.default.fileExists(atPath: systemSoundPath) {
            // Try system sound
            var soundID: SystemSoundID = 0
            let soundURL = URL(fileURLWithPath: systemSoundPath)
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else {
            // Fallback: play a simple system beep
            NSSound.beep()
        }
    }
}
