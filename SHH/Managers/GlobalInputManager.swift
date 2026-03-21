import ApplicationServices
import CoreGraphics
import Foundation

/// Intercepts system-wide keyboard events via CGEvent Tap to detect Fn key
/// press/release transitions and Space key presses for Lock-in mode.
///
/// Requires Accessibility permission (AXIsProcessTrusted) before the tap
/// can be installed. The tap listens in read-only mode (.listenOnly) and
/// does not block or modify any events.
///
/// The RunLoop source is added to the main RunLoop, so all callbacks
/// fire on the main thread.
final class GlobalInputManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: CGEventFlags = []

    /// Modifier keys that must NOT change simultaneously with Fn for the
    /// event to be considered an isolated Fn key event.
    private static let otherModifierMask = CGEventFlags(rawValue:
        CGEventFlags.maskShift.rawValue
        | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue
        | CGEventFlags.maskCommand.rawValue
        | CGEventFlags.maskAlphaShift.rawValue
    )

    /// Called when the Fn key is pressed (flag appeared in mask).
    var onFnPress: (() -> Void)?

    /// Called when the Fn key is released (flag disappeared from mask).
    var onFnRelease: (() -> Void)?

    /// Called when the Space key is pressed (.keyDown with keyCode 49).
    var onSpacePress: (() -> Void)?

    /// Called when the system disables the event tap and re-enablement is attempted.
    var onTapDisabled: (() -> Void)?

    private(set) var isRunning = false

    /// Installs a CGEvent Tap on the current session for `.flagsChanged`
    /// and `.keyDown` events.
    ///
    /// - Returns: `true` if the tap was successfully installed, `false` if
    ///   Accessibility permission is missing or the tap could not be created.
    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }
        guard AXIsProcessTrusted() else { return false }

        let eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: globalInputEventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        return true
    }

    /// Removes the CGEvent Tap and stops intercepting events.
    func stop() {
        guard isRunning else { return }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        previousFlags = []
        isRunning = false
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // System disabled the tap — attempt to re-enable it
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            onTapDisabled?()

        case .flagsChanged:
            handleFlagsChanged(event: event)

        case .keyDown:
            handleKeyDown(event: event)

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(event: CGEvent) {
        let currentFlags = event.flags
        let diff = CGEventFlags(rawValue: previousFlags.rawValue ^ currentFlags.rawValue)
        previousFlags = currentFlags

        // Only respond if the Fn flag changed
        guard diff.contains(.maskSecondaryFn) else { return }

        // Ignore when other modifier keys changed simultaneously
        guard diff.intersection(Self.otherModifierMask).isEmpty else { return }

        if currentFlags.contains(.maskSecondaryFn) {
            onFnPress?()
        } else {
            onFnRelease?()
        }
    }

    private func handleKeyDown(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // Space bar keyCode = 49
        if keyCode == 49 {
            onSpacePress?()
        }
    }

    deinit {
        stop()
    }
}

// MARK: - CGEvent Tap Callback

/// Top-level C-compatible callback for the CGEvent Tap.
/// Uses the refcon pointer to dispatch events to the GlobalInputManager instance.
private func globalInputEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<GlobalInputManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handleEvent(proxy: proxy, type: type, event: event)
}
