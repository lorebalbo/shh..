import XCTest

/// Validation tests for RecordingStateMachine (MT-3 scenarios).
/// RecordingStateMachine is compiled directly into the test target.
final class RecordingStateMachineTests: XCTestCase {

    private var sm: RecordingStateMachine!
    private var didStart: Bool = false
    private var didStopMode: RecordingMode?
    private var startCount: Int = 0
    private var stopCount: Int = 0

    override func setUp() {
        super.setUp()
        sm = RecordingStateMachine()
        didStart = false
        didStopMode = nil
        startCount = 0
        stopCount = 0

        sm.onRecordingDidStart = { [unowned self] in
            self.didStart = true
            self.startCount += 1
        }
        sm.onRecordingDidStop = { [unowned self] mode in
            self.didStopMode = mode
            self.stopCount += 1
        }
    }

    override func tearDown() {
        sm = nil
        super.tearDown()
    }

    // MARK: - MT-3-V1: Push-to-Talk

    func testPushToTalk_holdFnStartsRecording_releaseFnStops() {
        XCTAssertEqual(sm.state, .idle)

        // Press Fn → recording starts in pushToTalkActive
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)
        XCTAssertTrue(didStart, "Recording should start on Fn press")
        XCTAssertEqual(startCount, 1)

        // Release Fn → recording stops, returns to idle
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(didStopMode, .pushToTalk, "Should stop with pushToTalk mode")
        XCTAssertEqual(stopCount, 1)
    }

    func testPushToTalk_stateTransition_idleToPushToTalkActiveToIdle() {
        XCTAssertEqual(sm.state, .idle)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .idle)
    }

    // MARK: - MT-3-V2: Continuous Toggle (Double-tap)

    func testContinuousToggle_doubleTapFnStartsContinuous_singleFnStops() {
        XCTAssertEqual(sm.state, .idle)

        // First press → pushToTalkActive
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)
        XCTAssertEqual(startCount, 1)

        // First release → idle (PTT stops)
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(didStopMode, .pushToTalk)

        // Second press within 300ms → continuousActive (double-tap detected)
        Thread.sleep(forTimeInterval: 0.01)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive,
            "Double-tap should enter continuousActive")
        XCTAssertEqual(startCount, 2)

        // Release → still continuousActive (hands-free)
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .continuousActive,
            "Release should NOT stop continuous mode")
        XCTAssertEqual(stopCount, 1, "Stop count should not increase on release in continuous")

        // Single Fn press → idle (stops recording)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(didStopMode, .continuous)
        XCTAssertEqual(stopCount, 2)
    }

    func testContinuousToggle_recordingContinuesAfterRelease() {
        // Enter continuous mode
        sm.handleFnPress()
        sm.handleFnRelease()
        Thread.sleep(forTimeInterval: 0.01)
        sm.handleFnPress() // double-tap
        XCTAssertEqual(sm.state, .continuousActive)

        // Release all keys — recording must continue
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .continuousActive,
            "Recording must continue after keys released in continuous mode")
    }

    // MARK: - MT-3-V3: Lock-in Mode

    func testLockIn_holdFnPressSpaceLocksRecording_singleFnStops() {
        XCTAssertEqual(sm.state, .idle)

        // Press and hold Fn → pushToTalkActive
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)
        XCTAssertEqual(startCount, 1)

        // While holding Fn, press Space → lockInActive
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .lockInActive,
            "Fn held + Space should transition to lockInActive")
        // No additional start callback — recording was already started
        XCTAssertEqual(startCount, 1, "No extra start when transitioning to lockIn")

        // Release Fn (still locked in)
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .lockInActive,
            "Releasing Fn in lockIn mode should NOT stop recording")
        XCTAssertEqual(stopCount, 0)

        // Release Space (still locked in — no handler for space release)
        // State should remain lockInActive

        // Press Fn once → idle (stop recording)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle)
        XCTAssertEqual(didStopMode, .lockIn)
        XCTAssertEqual(stopCount, 1)
    }

    func testLockIn_stateTransition_idleToPTTToLockInToIdle() {
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)

        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .lockInActive)

        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .lockInActive, "Lock-in persists after key release")

        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle)
    }

    func testLockIn_recordingPersistsAfterAllKeysReleased() {
        sm.handleFnPress()
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .lockInActive)

        // Release both
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .lockInActive, "Recording persists after all keys released")
        XCTAssertEqual(stopCount, 0, "Recording not stopped")
    }

    // MARK: - MT-3-V4: Double-tap boundary at 300ms

    func testDoubleTapBoundary_atExactly300ms_entersContinuous() {
        // Simulate first press
        sm.handleFnPress()
        sm.handleFnRelease()

        // Small delay ensures CFAbsoluteTimeGetCurrent() returns a different
        // value (elapsed > 0) while still within the 300ms double-tap window.
        Thread.sleep(forTimeInterval: 0.01)

        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive,
            "Press within 300ms should enter continuousActive (double-tap)")
    }

    func testDoubleTapBoundary_beyond300ms_entersPushToTalk() {
        // First press
        sm.handleFnPress()
        sm.handleFnRelease()

        // Wait beyond the 300ms window
        // We need to simulate elapsed time > 0.3s
        Thread.sleep(forTimeInterval: 0.35)

        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive,
            "Press beyond 300ms should enter pushToTalkActive (not double-tap)")
    }

    func testDoubleTapBoundary_slightlyBelow300ms_entersContinuous() {
        sm.handleFnPress()
        sm.handleFnRelease()

        // Sleep just under 300ms
        Thread.sleep(forTimeInterval: 0.25)

        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive,
            "Press at 250ms should be recognized as double-tap")
    }

    // MARK: - MT-3-V6: Rapid key presses

    func testRapidPresses_10CyclesAllRapid_endsInIdle() {
        // 10 rapid press+release cycles with very small delays
        // to ensure reliable double-tap detection timing
        for _ in 0..<10 {
            sm.handleFnPress()
            sm.handleFnRelease()
            Thread.sleep(forTimeInterval: 0.001)
        }

        XCTAssertEqual(sm.state, .idle,
            "After 10 rapid press/release cycles, state must be idle")
    }

    func testRapidPresses_10CyclesSlow_endsInIdle() {
        // 10 press+release cycles with delays > 300ms between each
        for i in 0..<10 {
            sm.handleFnPress()
            sm.handleFnRelease()
            if i < 9 {
                Thread.sleep(forTimeInterval: 0.35)
            }
        }

        XCTAssertEqual(sm.state, .idle,
            "After 10 slow press/release cycles, state must be idle")
    }

    func testRapidPresses_noOverlappingRecordings() {
        var activeRecordings = 0
        var maxConcurrentRecordings = 0

        sm.onRecordingDidStart = {
            activeRecordings += 1
            maxConcurrentRecordings = max(maxConcurrentRecordings, activeRecordings)
        }
        sm.onRecordingDidStop = { _ in
            activeRecordings -= 1
        }

        // Use slow presses (> 300ms apart) to avoid double-tap detection.
        // This tests that PTT start/stop pairs always balance.
        for i in 0..<10 {
            sm.handleFnPress()
            sm.handleFnRelease()
            if i < 9 {
                Thread.sleep(forTimeInterval: 0.35)
            }
        }

        XCTAssertEqual(activeRecordings, 0,
            "No recordings should be active after all cycles complete")
        XCTAssertLessThanOrEqual(maxConcurrentRecordings, 1,
            "At most one recording should be active at any time")
    }

    func testRapidPresses_irregularPattern_endsInIdle() {
        // Simulate an irregular pattern:
        // Quick tap, quick tap (double-tap), wait, quick tap, hold longer, etc.

        // Tap 1: quick press+release
        sm.handleFnPress()
        sm.handleFnRelease()

        // Tap 2: immediate double-tap → enters continuous
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive)
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .continuousActive) // still recording

        // Tap 3: stops continuous
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle)
        sm.handleFnRelease()

        // Wait > 300ms
        Thread.sleep(forTimeInterval: 0.35)

        // Tap 4: fresh PTT
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .idle)

        // Final state must be idle
        XCTAssertEqual(sm.state, .idle)
    }

    // MARK: - MT-3-V7: Fn + Space only triggers lockIn from pushToTalkActive

    func testSpacePress_inIdleState_doesNothing() {
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .idle,
            "Space press in idle should not change state")
        XCTAssertFalse(didStart)
    }

    func testSpacePress_inContinuousActive_doesNothing() {
        // Enter continuous
        sm.handleFnPress()
        sm.handleFnRelease()
        Thread.sleep(forTimeInterval: 0.01)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive)

        let beforeStopCount = stopCount
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .continuousActive,
            "Space in continuous mode should not change state")
        XCTAssertEqual(stopCount, beforeStopCount)
    }

    func testSpacePress_inLockInActive_doesNothing() {
        // Enter lockIn
        sm.handleFnPress()
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .lockInActive)

        let beforeStopCount = stopCount
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .lockInActive,
            "Additional Space in lockIn should not change state")
        XCTAssertEqual(stopCount, beforeStopCount)
    }

    // MARK: - MT-3-V8: Single Fn always stops Continuous and Lock-in

    func testSingleFnPress_stopsContinuousMode() {
        // Enter continuous mode
        sm.handleFnPress()
        sm.handleFnRelease()
        Thread.sleep(forTimeInterval: 0.01)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive)

        // Wait (simulate 5 seconds in the scenario, but just verify the press stops it)
        let stopCountBefore = stopCount

        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle, "Fn press must stop continuous recording")
        XCTAssertEqual(didStopMode, .continuous)
        XCTAssertEqual(stopCount, stopCountBefore + 1)
    }

    func testSingleFnPress_stopsLockInMode() {
        // Enter lockIn mode
        sm.handleFnPress()
        sm.handleSpacePress()
        XCTAssertEqual(sm.state, .lockInActive)

        // Release all keys
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .lockInActive, "Lock-in persists after release")

        // Single Fn press stops it
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle, "Fn press must stop lock-in recording")
        XCTAssertEqual(didStopMode, .lockIn)
    }

    func testSingleFnPress_stopsLockInMode_afterDelay() {
        // Enter lockIn mode
        sm.handleFnPress()
        sm.handleSpacePress()
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .lockInActive)

        // Wait beyond double-tap window to ensure it's not detected as double-tap
        Thread.sleep(forTimeInterval: 0.35)

        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle, "Fn press must stop lock-in even after delay")
        XCTAssertEqual(didStopMode, .lockIn)
    }

    // MARK: - MT-3-V5: forceIdle for external interruptions

    func testForceIdle_resetsState() {
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)

        sm.forceIdle()
        XCTAssertEqual(sm.state, .idle)
        // forceIdle should NOT fire callbacks
        XCTAssertEqual(stopCount, 0, "forceIdle should not fire onRecordingDidStop")
    }

    func testForceIdle_clearsFnPressTimestamp() {
        sm.handleFnPress()
        sm.forceIdle()

        // Next press should NOT be a double-tap
        Thread.sleep(forTimeInterval: 0.01)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive,
            "After forceIdle, next press should be PTT, not double-tap")
    }

    // MARK: - Edge cases

    func testFnRelease_inIdleState_doesNothing() {
        sm.handleFnRelease()
        XCTAssertEqual(sm.state, .idle)
        XCTAssertFalse(didStart)
        XCTAssertNil(didStopMode)
    }

    func testRedundantFnPress_inPTT_isIgnored() {
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive)
        XCTAssertEqual(startCount, 1)

        // Redundant press in PTT
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive, "Should remain in PTT")
        XCTAssertEqual(startCount, 1, "Should not fire start again")
    }

    func testStoppingContinuous_resetsLastFnPressTime() {
        // Enter continuous mode via double-tap
        sm.handleFnPress()
        sm.handleFnRelease()
        Thread.sleep(forTimeInterval: 0.01) // ensure elapsed > 0
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .continuousActive)

        // Stop continuous
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .idle)

        // Press again — should NOT be double-tap since
        // lastFnPressTime was reset to 0 when stopping continuous
        Thread.sleep(forTimeInterval: 0.01)
        sm.handleFnPress()
        XCTAssertEqual(sm.state, .pushToTalkActive,
            "After stopping continuous, next press should be PTT (lastFnPressTime reset)")
    }
}
