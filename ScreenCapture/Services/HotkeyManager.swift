import Foundation
import Carbon.HIToolbox
import AppKit

/// Actor responsible for registering and managing global keyboard shortcuts.
/// Uses the Carbon RegisterEventHotKey API for sandbox-compatible global hotkeys.
actor HotkeyManager {
    // MARK: - Types

    /// Represents a registered hotkey
    struct Registration: Sendable {
        let id: UInt32
        let keyCode: UInt32
        let modifiers: UInt32
    }

    /// Handler closure type for hotkey events
    typealias HotkeyHandler = @Sendable () -> Void

    // MARK: - Properties

    /// Shared instance for app-wide hotkey management
    static let shared = HotkeyManager()

    /// The app signature for Carbon hotkey registration (4 char code: "SCRN")
    private let signature: OSType = OSType("SCRN".fourCharCode)

    /// Counter for generating unique hotkey IDs
    private var nextHotkeyID: UInt32 = 1

    /// Registered hotkeys by ID
    private var registrations: [UInt32: EventHotKeyRef] = [:]

    /// Handlers for each hotkey ID
    private var handlers: [UInt32: HotkeyHandler] = [:]

    /// Event handler reference
    private var eventHandlerRef: EventHandlerRef?

    /// Whether the event handler is installed
    private var isEventHandlerInstalled = false

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Registers a global hotkey with the given key code and modifiers.
    /// - Parameters:
    ///   - keyCode: The virtual key code (use kVK_ constants from Carbon)
    ///   - modifiers: The modifier flags (Carbon format)
    ///   - handler: The closure to execute when the hotkey is pressed
    /// - Returns: A registration object that can be used to unregister the hotkey
    /// - Throws: ScreenCaptureError.hotkeyRegistrationFailed if registration fails
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping HotkeyHandler
    ) throws -> Registration {
        // Install event handler if not already installed
        if !isEventHandlerInstalled {
            try installEventHandler()
        }

        // Generate unique ID for this hotkey
        let hotkeyID = nextHotkeyID
        nextHotkeyID += 1

        // Create hotkey ID structure
        let hotKeyID = EventHotKeyID(signature: signature, id: hotkeyID)

        // Register the hotkey
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let ref = hotKeyRef else {
            throw ScreenCaptureError.hotkeyRegistrationFailed(keyCode: keyCode)
        }

        // Store registration and handler
        registrations[hotkeyID] = ref
        handlers[hotkeyID] = handler

        return Registration(id: hotkeyID, keyCode: keyCode, modifiers: modifiers)
    }

    /// Registers a global hotkey from a KeyboardShortcut.
    /// - Parameters:
    ///   - shortcut: The keyboard shortcut to register
    ///   - handler: The closure to execute when the hotkey is pressed
    /// - Returns: A registration object that can be used to unregister the hotkey
    /// - Throws: ScreenCaptureError.hotkeyRegistrationFailed if registration fails
    func register(
        shortcut: KeyboardShortcut,
        handler: @escaping HotkeyHandler
    ) throws -> Registration {
        try register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers,
            handler: handler
        )
    }

    /// Unregisters a previously registered hotkey.
    /// - Parameter registration: The registration to unregister
    func unregister(_ registration: Registration) {
        guard let ref = registrations[registration.id] else { return }

        UnregisterEventHotKey(ref)
        registrations.removeValue(forKey: registration.id)
        handlers.removeValue(forKey: registration.id)
    }

    /// Unregisters all hotkeys.
    func unregisterAll() {
        for (_, ref) in registrations {
            UnregisterEventHotKey(ref)
        }
        registrations.removeAll()
        handlers.removeAll()
    }

    // MARK: - Event Handler

    /// Called when a hotkey event is received
    nonisolated func handleHotkeyEvent(id: UInt32) {
        NSLog("[HotkeyManager] handleHotkeyEvent called with id: %u", id)
        Task {
            await invokeHandler(for: id)
        }
    }

    /// Invokes the handler for the given hotkey ID
    private func invokeHandler(for id: UInt32) {
        NSLog("[HotkeyManager] invokeHandler for id: %u", id)
        guard let handler = handlers[id] else {
            NSLog("[HotkeyManager] No handler found for id: %u", id)
            return
        }
        NSLog("[HotkeyManager] Calling handler")
        handler()
    }

    /// Installs the Carbon event handler for hotkey events
    private func installEventHandler() throws {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Store self reference for callback
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyEventHandler,
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )

        guard status == noErr else {
            throw ScreenCaptureError.hotkeyRegistrationFailed(keyCode: 0)
        }

        isEventHandlerInstalled = true
    }
}

// MARK: - String Extension for FourCharCode

private extension String {
    /// Converts a 4-character string to an OSType (FourCharCode)
    var fourCharCode: UInt32 {
        var result: UInt32 = 0
        for char in self.prefix(4).utf8 {
            result = (result << 8) | UInt32(char)
        }
        return result
    }
}

// MARK: - Carbon Event Handler

/// Global Carbon event handler callback
private func hotkeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    NSLog("[HotkeyManager] hotkeyEventHandler called!")

    guard let event = event,
          let userData = userData else {
        NSLog("[HotkeyManager] Missing event or userData")
        return OSStatus(eventNotHandledErr)
    }

    // Get the hotkey ID from the event
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr else {
        NSLog("[HotkeyManager] GetEventParameter failed: %d", status)
        return OSStatus(eventNotHandledErr)
    }

    NSLog("[HotkeyManager] Hotkey ID: %u", hotKeyID.id)

    // Get the HotkeyManager instance and handle the event
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotkeyEvent(id: hotKeyID.id)

    return noErr
}
