import CoreAudio
import XCTest

/// Tests for SystemAudioMuter against a fake output, so the Mac's real sound is never touched.
final class SystemAudioMuterTests: XCTestCase {

    private final class FakeOutput: SystemAudioOutput {
        var defaultDevice: AudioObjectID? = 42
        /// nil = the device has no mute switch we can change.
        var muted: [AudioObjectID: Bool] = [42: false]
        /// nil = the device has no volume we can change.
        var volumes: [AudioObjectID: Float32] = [42: 0.6]
        var failsToMute = false

        func isMuted(_ device: AudioObjectID) -> Bool? { muted[device] }

        func setMuted(_ muted: Bool, on device: AudioObjectID) -> Bool {
            guard self.muted[device] != nil, !failsToMute else { return false }
            self.muted[device] = muted
            return true
        }

        func volume(_ device: AudioObjectID) -> Float32? { volumes[device] }

        func setVolume(_ volume: Float32, on device: AudioObjectID) -> Bool {
            guard volumes[device] != nil else { return false }
            volumes[device] = volume
            return true
        }
    }

    private var output: FakeOutput!
    private var muter: SystemAudioMuter!

    override func setUp() {
        super.setUp()
        output = FakeOutput()
        muter = SystemAudioMuter(output: output)
    }

    func testMuteUsesTheMuteSwitchAndLeavesVolumeAlone() {
        muter.mute()

        XCTAssertEqual(output.muted[42], true)
        XCTAssertEqual(output.volumes[42], 0.6)
        XCTAssertTrue(muter.isSilencing)
    }

    func testRestoreUnmutes() {
        muter.mute()
        muter.restore()

        XCTAssertEqual(output.muted[42], false)
        XCTAssertEqual(output.volumes[42], 0.6)
        XCTAssertFalse(muter.isSilencing)
    }

    func testAlreadyMutedOutputStaysMutedAfterRestore() {
        output.muted[42] = true

        muter.mute()
        XCTAssertFalse(muter.isSilencing)
        muter.restore()

        XCTAssertEqual(output.muted[42], true)
    }

    func testDeviceWithoutMuteSwitchFallsBackToVolume() {
        output.muted = [:]

        muter.mute()
        XCTAssertEqual(output.volumes[42], 0)

        muter.restore()
        XCTAssertEqual(output.volumes[42], 0.6)
    }

    func testFailedMuteFallsBackToVolume() {
        output.failsToMute = true

        muter.mute()
        XCTAssertEqual(output.volumes[42], 0)

        muter.restore()
        XCTAssertEqual(output.volumes[42], 0.6)
    }

    func testVolumeAlreadyAtZeroIsLeftAlone() {
        output.muted = [:]
        output.volumes[42] = 0

        muter.mute()
        XCTAssertFalse(muter.isSilencing)
    }

    func testSecondMuteKeepsTheOriginalStateToRestore() {
        output.muted = [:]
        muter.mute()
        muter.mute()
        muter.restore()

        XCTAssertEqual(output.volumes[42], 0.6)
    }

    func testRestoreTargetsTheDeviceThatWasMuted() {
        output.muted[7] = false
        muter.mute()

        output.defaultDevice = 7 // e.g. headphones plugged in mid-recording
        muter.restore()

        XCTAssertEqual(output.muted[42], false)
        XCTAssertEqual(output.muted[7], false)
    }

    func testRestoreWithoutMuteDoesNothing() {
        muter.restore()

        XCTAssertEqual(output.muted[42], false)
        XCTAssertEqual(output.volumes[42], 0.6)
    }

    func testNoOutputDeviceDoesNothing() {
        output.defaultDevice = nil

        muter.mute()
        XCTAssertFalse(muter.isSilencing)
    }
}
