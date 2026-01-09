import Foundation
import AppKit
import Carbon.HIToolbox

/// Global hotkey configuration for capture shortcuts.
struct KeyboardShortcut: Equatable, Codable, Sendable {
    /// Virtual key code (Carbon key codes)
    let keyCode: UInt32

    /// Modifier flags (Cmd, Shift, Option, Control)
    let modifiers: UInt32

    // MARK: - Initialization

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Creates a shortcut from NSEvent modifier flags
    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = Self.carbonModifiers(from: modifierFlags)
    }

    // MARK: - Default Shortcuts

    /// Default full screen capture shortcut: Command + Shift + 3
    static let fullScreenDefault = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_3),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// Default selection capture shortcut: Command + Shift + 4
    static let selectionDefault = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_4),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    /// Default window capture shortcut: Command + Shift + 6
    static let windowDefault = KeyboardShortcut(
        keyCode: UInt32(kVK_ANSI_6),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    // MARK: - Validation

    /// Checks if the shortcut includes at least one modifier key
    var hasRequiredModifiers: Bool {
        let requiredMask = UInt32(cmdKey | controlKey | optionKey)
        return (modifiers & requiredMask) != 0
    }

    /// Validates this shortcut configuration
    var isValid: Bool {
        hasRequiredModifiers && keyCode != 0
    }

    // MARK: - Display

    /// Human-readable string representation (e.g., "Cmd+Shift+3")
    var displayString: String {
        var parts: [String] = []

        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Ctrl")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Opt")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Cmd")
        }

        if let keyString = Self.keyCodeToString(keyCode) {
            parts.append(keyString)
        }

        return parts.joined(separator: "+")
    }

    /// Symbol-based string representation (e.g., "^3")
    var symbolString: String {
        var symbols = ""

        if modifiers & UInt32(controlKey) != 0 {
            symbols += "^"
        }
        if modifiers & UInt32(optionKey) != 0 {
            symbols += "~"
        }
        if modifiers & UInt32(shiftKey) != 0 {
            symbols += "$"
        }
        if modifiers & UInt32(cmdKey) != 0 {
            symbols += "@"
        }

        if let keyString = Self.keyCodeToString(keyCode) {
            symbols += keyString
        }

        return symbols
    }

    // MARK: - Modifier Conversion

    /// Converts NSEvent.ModifierFlags to Carbon modifier mask
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0

        if flags.contains(.command) {
            carbonMods |= UInt32(cmdKey)
        }
        if flags.contains(.shift) {
            carbonMods |= UInt32(shiftKey)
        }
        if flags.contains(.option) {
            carbonMods |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            carbonMods |= UInt32(controlKey)
        }

        return carbonMods
    }

    /// Converts Carbon modifier mask to NSEvent.ModifierFlags
    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if modifiers & UInt32(cmdKey) != 0 {
            flags.insert(.command)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            flags.insert(.shift)
        }
        if modifiers & UInt32(optionKey) != 0 {
            flags.insert(.option)
        }
        if modifiers & UInt32(controlKey) != 0 {
            flags.insert(.control)
        }

        return flags
    }

    // MARK: - Key Code to String

    /// Converts a virtual key code to its string representation
    private static func keyCodeToString(_ keyCode: UInt32) -> String? {
        switch Int(keyCode) {
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        default: return nil
        }
    }
}
