import Foundation

/// The recording mode that was active when recording stopped.
enum RecordingMode {
    case pushToTalk
    case continuous
    case lockIn
}

/// Enum-based state machine managing recording mode transitions driven by
/// Fn key, Space key, and Escape key events from GlobalInputManager.
///
/// States: idle, pushToTalkActive, continuousActive, lockInActive.
///
/// Transitions:
/// - idle + Fn press → pushToTalkActive (or continuousActive on double-tap)
/// - pushToTalkActive + Fn release → idle (Push-to-Talk complete)
/// - pushToTalkActive + Space press → lockInActive (Lock-in activated)
/// - continuousActive + Fn press → idle (stop recording)
/// - lockInActive + Fn press → idle (stop recording)
/// - any active + Esc press → idle (cancel recording)
///
/// Double-tap detection: two Fn presses within 300ms enter continuousActive.
final class RecordingStateMachine {

    enum State {
        case idle
        case pushToTalkActive
        case continuousActive
        case lockInActive
    }

    private(set) var state: State = .idle

    /// Time window (in seconds) for double-tap detection.
    private let doubleTapWindow: CFAbsoluteTime = 0.3

    /// Timestamp of the last Fn press event while in idle state.
    private var lastFnPressTime: CFAbsoluteTime = 0

    /// Called when recording should start (state machine entered an active state).
    var onRecordingDidStart: (() -> Void)?

    /// Called when recording should stop (state machine returned to idle).
    /// The parameter indicates which recording mode was active.
    var onRecordingDidStop: ((RecordingMode) -> Void)?

    /// Called when recording is cancelled (e.g. via Escape key).
    /// The audio buffer should be discarded without transcription.
    var onRecordingDidCancel: (() -> Void)?

    /// Called when the state machine is force-reset to idle (e.g. hardware error,
    /// audio engine failure). No recording mode is available; callers should treat
    /// this as an abrupt stop without transcription.
    var onForcedIdle: (() -> Void)?

    // MARK: - Event Handlers

    /// Returns `true` if the event was consumed and should be suppressed.
    @discardableResult
    func handleFnPress() -> Bool {
        switch state {
        case .idle:
            let now = CFAbsoluteTimeGetCurrent()
            let elapsed = now - lastFnPressTime
            lastFnPressTime = now

            if elapsed <= doubleTapWindow && elapsed > 0 {
                // Double-tap detected → Continuous mode
                state = .continuousActive
            } else {
                // Single press → Push-to-Talk
                state = .pushToTalkActive
            }
            onRecordingDidStart?()
            return true

        case .continuousActive:
            // Single press stops Continuous recording
            lastFnPressTime = 0
            state = .idle
            onRecordingDidStop?(.continuous)
            return true

        case .lockInActive:
            // Single press stops Lock-in recording
            lastFnPressTime = 0
            state = .idle
            onRecordingDidStop?(.lockIn)
            return true

        case .pushToTalkActive:
            // Already in PTT — ignore redundant press
            return true
        }
    }

    /// Returns `true` if the event was consumed and should be suppressed.
    @discardableResult
    func handleFnRelease() -> Bool {
        switch state {
        case .pushToTalkActive:
            // Release in PTT → stop recording
            state = .idle
            onRecordingDidStop?(.pushToTalk)
            return true

        case .continuousActive, .lockInActive:
            // Fn release while in continuous/lockIn — no state change but
            // suppress the event to prevent macOS emoji picker detection
            return true

        case .idle:
            return false
        }
    }

    /// Returns `true` if the event was consumed and should be suppressed.
    @discardableResult
    func handleSpacePress() -> Bool {
        switch state {
        case .pushToTalkActive:
            // Fn held + Space → Lock-in mode (recording continues)
            state = .lockInActive
            return true

        default:
            return false
        }
    }

    /// Returns `true` if the event was consumed and should be suppressed.
    @discardableResult
    func handleEscPress() -> Bool {
        switch state {
        case .pushToTalkActive, .continuousActive, .lockInActive:
            lastFnPressTime = 0
            state = .idle
            onRecordingDidCancel?()
            return true

        case .idle:
            return false
        }
    }

    /// Forcefully resets the state machine to idle without firing callbacks.
    /// Used when an external interruption (e.g. microphone disconnect)
    /// stops recording outside the normal state machine flow.
    func forceIdle() {
        lastFnPressTime = 0
        state = .idle
        onForcedIdle?()
    }

    /// Enters lock-in mode directly from idle (triggered by overlay widget tap).
    /// Does nothing if already in an active recording state.
    func startLockIn() {
        guard state == .idle else { return }
        state = .lockInActive
        onRecordingDidStart?()
    }
}
