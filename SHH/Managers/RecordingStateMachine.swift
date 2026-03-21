import Foundation

/// The recording mode that was active when recording stopped.
enum RecordingMode {
    case pushToTalk
    case continuous
    case lockIn
}

/// Enum-based state machine managing recording mode transitions driven by
/// Fn key and Space key events from GlobalInputManager.
///
/// States: idle, pushToTalkActive, continuousActive, lockInActive.
///
/// Transitions:
/// - idle + Fn press → pushToTalkActive (or continuousActive on double-tap)
/// - pushToTalkActive + Fn release → idle (Push-to-Talk complete)
/// - pushToTalkActive + Space press → lockInActive (Lock-in activated)
/// - continuousActive + Fn press → idle (stop recording)
/// - lockInActive + Fn press → idle (stop recording)
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

    /// Called when the state machine is force-reset to idle (e.g. hardware error,
    /// audio engine failure). No recording mode is available; callers should treat
    /// this as an abrupt stop without transcription.
    var onForcedIdle: (() -> Void)?

    // MARK: - Event Handlers

    func handleFnPress() {
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

        case .continuousActive:
            // Single press stops Continuous recording
            lastFnPressTime = 0
            state = .idle
            onRecordingDidStop?(.continuous)

        case .lockInActive:
            // Single press stops Lock-in recording
            lastFnPressTime = 0
            state = .idle
            onRecordingDidStop?(.lockIn)

        case .pushToTalkActive:
            // Already in PTT — ignore redundant press
            break
        }
    }

    func handleFnRelease() {
        switch state {
        case .pushToTalkActive:
            // Release in PTT → stop recording
            state = .idle
            onRecordingDidStop?(.pushToTalk)

        default:
            // Release is irrelevant in continuous, lockIn, or idle
            break
        }
    }

    func handleSpacePress() {
        switch state {
        case .pushToTalkActive:
            // Fn held + Space → Lock-in mode (recording continues)
            state = .lockInActive

        default:
            break
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
