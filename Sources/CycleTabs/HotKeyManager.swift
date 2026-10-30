import AppKit
import Carbon.HIToolbox

/// Registers system-wide hot keys through Carbon's `RegisterEventHotKey`.
///
/// This is used instead of `NSEvent.addGlobalMonitorForEvents`, which requires
/// the Accessibility permission and cannot swallow the key press.
@MainActor
final class HotKeyManager {

    static let shared = HotKeyManager()

    /// Virtual key codes and modifier masks expressed in Carbon terms.
    struct Shortcut {
        let keyCode: UInt32
        let modifiers: UInt32

        var displayString: String {
            var parts = ""
            if modifiers & UInt32(cmdKey) != 0 { parts += "⌘" }
            if modifiers & UInt32(controlKey) != 0 { parts += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { parts += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { parts += "⇧" }
            return parts + Self.keyLabel(for: keyCode)
        }

        private static func keyLabel(for keyCode: UInt32) -> String {
            switch Int(keyCode) {
            case kVK_Tab: return "⇥"
            case kVK_ANSI_N: return "N"
            case kVK_ANSI_P: return "P"
            default: return "?"
            }
        }
    }

    static let nextTab = Shortcut(keyCode: UInt32(kVK_Tab), modifiers: UInt32(controlKey | optionKey))
    static let previousTab = Shortcut(
        keyCode: UInt32(kVK_Tab),
        modifiers: UInt32(controlKey | optionKey | shiftKey)
    )

    private var actions: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    private init() {}

    /// Registers a shortcut. Returns `false` when macOS refuses (for example
    /// because another app already owns the combination).
    @discardableResult
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4359_5442), id: id) // 'CYTB'
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return false
        }

        actions[id] = action
        hotKeyRefs.append(hotKeyRef)
        return true
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            cycleTabsHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

/// Carbon event callbacks are C function pointers, so this must not capture.
/// Carbon delivers hot key events on the main thread/run loop.
private func cycleTabsHotKeyHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

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
    guard status == noErr else { return status }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.fire(hotKeyID.id)
    }
    return noErr
}
