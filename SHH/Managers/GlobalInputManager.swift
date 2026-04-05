import ApplicationServices
import CoreGraphics
import Foundation

/// Intercepts system-wide keyboard events via CGEvent Tap to detect Fn key
/// press/release transitions, Space key presses for Lock-in mode, and
/// Escape key presses for recording cancellation.
///
/// Requires Accessibility permission (AXIsProcessTrusted) before the tap
/// can be installed. The tap runs in active-filter mode (.defaultTap) so
/// that consumed events (e.g. Space during lock-in, isolated Fn presses)
/// are suppressed and never reach the focused application or macOS.
///
/// **Fn/Globe key strategy:** The Fn/Globe key on macOS is partially
/// handled at the HID level *before* CGEvent taps. Returning `nil`
/// (suppressing) flagsChanged events does not reliably prevent macOS from
/// triggering the emoji picker. Instead, when we consume an Fn event we
/// *strip the `.maskSecondaryFn` flag* from the event — making the Fn
/// state change invisible to macOS while still forwarding other modifier
/// changes. keyDown/keyUp events for the Globe key (keyCodes 63 & 179)
/// are also intercepted and suppressed when the Fn press was consumed.
///
/// The RunLoop source is added to the main RunLoop, so all callbacks
/// fire on the main thread.
final class GlobalInputManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var previousFlags: CGEventFlags = []

    /// Tracks whether the most recent Fn press was consumed by the app.
    /// Persists across the press → release → keyUp cycle so that all
    /// related events for the same physical key action are handled.
    /// Reset on the next Fn press.
    private var fnPressConsumed = false

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
    /// Return `true` to consume the event (prevent it from reaching macOS).
    var onFnPress: (() -> Bool)?

    /// Called when the Fn key is released (flag disappeared from mask).
    /// Return `true` to consume the event.
    var onFnRelease: (() -> Bool)?

    /// Called when the Space key is pressed (.keyDown with keyCode 49).
    /// Return `true` to suppress the event.
    var onSpacePress: (() -> Bool)?

    /// Called when the Escape key is pressed (.keyDown with keyCode 53).
    /// Return `true` to suppress the event.
    var onEscPress: (() -> Bool)?

    /// Called when the system disables the event tap and re-enablement is attempted.
    var onTapDisabled: (() -> Void)?

    private(set) var isRunning = false

    /// Installs a CGEvent Tap on the current session for `.flagsChanged`,
    /// `.keyDown`, and `.keyUp` events.
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
            | (1 << CGEventType.keyUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
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
        fnPressConsumed = false
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
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            // For flagsChanged events we NEVER return nil. Instead we modify
            // the event's flags to strip `maskSecondaryFn` when consuming.
            // This is necessary because the Fn/Globe key emoji picker is
            // triggered at the HID level — suppressing the CGEvent alone
            // does not prevent it. Stripping the flag makes the Fn state
            // change invisible to macOS.
            handleFlagsChanged(event: event)
            return Unmanaged.passUnretained(event)

        case .keyDown:
            let suppress = handleKeyDown(event: event)
            return suppress ? nil : Unmanaged.passUnretained(event)

        case .keyUp:
            let suppress = handleKeyUp(event: event)
            return suppress ? nil : Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Processes Fn flag changes. When consumed, modifies `event.flags`
    /// in place to strip `.maskSecondaryFn` so macOS never detects the
    /// Fn key transition.
    private func handleFlagsChanged(event: CGEvent) {
        let currentFlags = event.flags
        let diff = CGEventFlags(rawValue: previousFlags.rawValue ^ currentFlags.rawValue)
        previousFlags = currentFlags

        // Only respond if the Fn flag changed
        guard diff.contains(.maskSecondaryFn) else { return }

        // Ignore when other modifier keys changed simultaneously
        guard diff.intersection(Self.otherModifierMask).isEmpty else { return }

        if currentFlags.contains(.maskSecondaryFn) {
            // Fn pressed
            let consumed = onFnPress?() ?? false
            fnPressConsumed = consumed
            if consumed {
                // Strip Fn flag — macOS will not see the Fn press
                event.flags = currentFlags.subtracting(.maskSecondaryFn)
            }
        } else {
            // Fn released
            if fnPressConsumed {
                // The corresponding press was consumed (Fn stripped),
                // so the system never saw Fn go down. This release is
                // effectively a no-op from the system's perspective
                // (Fn already absent in both previous and current flags).
                _ = onFnRelease?() ?? false
                // fnPressConsumed stays true until the next Fn press
                // so any trailing Globe keyUp is also suppressed.
                return
            }
            // Press was NOT consumed — let the release flow through normally
            _ = onFnRelease?() ?? false
        }
    }

    private func handleKeyDown(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 49: // Space bar
            return onSpacePress?() ?? false
        case 53: // Escape
            return onEscPress?() ?? false
        case 63, 179:
            // Fn/Globe key — on Apple Silicon Macs the Globe key generates
            // keyDown events in addition to flagsChanged. Suppress when
            // we consumed the Fn press to prevent the emoji picker.
            return fnPressConsumed
        default:
            return false
        }
    }

    private func handleKeyUp(event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch keyCode {
        case 63, 179:
            // Suppress Globe key-up if we consumed the Fn press
            return fnPressConsumed
        default:
            return false
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
