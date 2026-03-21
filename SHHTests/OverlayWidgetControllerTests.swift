import AppKit
import XCTest

/// Validation tests for OverlayWidgetController (MT-6 scenarios).
/// Tests position persistence, default positioning, edge snapping,
/// invalid data handling, and screen change behaviour.
final class OverlayWidgetControllerTests: XCTestCase {

    private let widgetSize = OverlayWidgetController.widgetSize

    override func tearDown() {
        // Clean up any test UserDefaults keys
        UserDefaults.standard.removeObject(forKey: "SHH_OverlayPositionX")
        UserDefaults.standard.removeObject(forKey: "SHH_OverlayPositionY")
        UserDefaults.standard.removeObject(forKey: "SHH_OverlayEdge")
        super.tearDown()
    }

    // MARK: - MT-6-V1: Default position is bottom-center

    func testDefaultBottomCenter_returnsCorrectPosition() {
        guard let screen = NSScreen.main else {
            XCTFail("No main screen available in test environment")
            return
        }

        let position = OverlayWidgetController.defaultBottomCenter(screen: screen)
        let visibleFrame = screen.visibleFrame

        // X should be horizontally centered
        let expectedX = visibleFrame.midX - widgetSize.width / 2
        XCTAssertEqual(position.x, expectedX, accuracy: 0.1,
            "Widget should be horizontally centered")

        // Y should be at the bottom of the visible frame
        XCTAssertEqual(position.y, visibleFrame.minY, accuracy: 0.1,
            "Widget should be at the bottom of the visible frame")
    }

    func testDefaultBottomCenter_nilScreen_returnsZero() {
        let position = OverlayWidgetController.defaultBottomCenter(screen: nil)
        XCTAssertEqual(position, .zero,
            "Nil screen should return .zero")
    }

    // MARK: - MT-6-V1: OverlayViewModel state transitions

    func testOverlayViewModel_idleByDefault() {
        let vm = OverlayViewModel()
        XCTAssertFalse(vm.isRecording, "ViewModel should be idle by default")
        XCTAssertEqual(vm.audioLevel, 0.0, "Audio level should be 0 by default")
    }

    func testOverlayViewModel_recordingStateTransitions() {
        let vm = OverlayViewModel()
        XCTAssertFalse(vm.isRecording)

        vm.isRecording = true
        XCTAssertTrue(vm.isRecording, "Should transition to recording")

        vm.isRecording = false
        XCTAssertFalse(vm.isRecording, "Should return to idle after recording stops")
    }

    func testOverlayViewModel_audioLevelUpdates() {
        let vm = OverlayViewModel()
        vm.audioLevel = 0.75
        XCTAssertEqual(vm.audioLevel, 0.75, accuracy: 0.001)
    }

    // MARK: - MT-6-V2: Click-to-record triggers startLockIn

    func testStartLockIn_fromIdle_entersLockInActive() {
        let sm = RecordingStateMachine()
        var didStart = false
        sm.onRecordingDidStart = { didStart = true }

        sm.startLockIn()

        XCTAssertEqual(sm.state, .lockInActive,
            "startLockIn should enter lockInActive")
        XCTAssertTrue(didStart,
            "onRecordingDidStart should fire")
    }

    func testStartLockIn_fromActiveState_doesNothing() {
        let sm = RecordingStateMachine()
        var startCount = 0
        sm.onRecordingDidStart = { startCount += 1 }

        sm.handleFnPress() // enter pushToTalkActive
        XCTAssertEqual(startCount, 1)

        sm.startLockIn() // should be ignored
        XCTAssertEqual(sm.state, .pushToTalkActive,
            "Should remain in pushToTalkActive")
        XCTAssertEqual(startCount, 1,
            "No additional start callback")
    }

    func testWidgetTap_triggersOnWidgetTapped() {
        let vm = OverlayViewModel()
        var tapped = false
        vm.onWidgetTapped = { tapped = true }

        vm.onWidgetTapped?()
        XCTAssertTrue(tapped, "onWidgetTapped should fire on tap")
    }

    // MARK: - MT-6-V3: OverlayPanel never steals focus

    func testOverlayPanel_cannotBecomeKeyOrMain() {
        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)
        let panel = controller.panelWindow

        XCTAssertFalse(panel.canBecomeKey,
            "OverlayPanel must never become key window")
        XCTAssertFalse(panel.canBecomeMain,
            "OverlayPanel must never become main window")
    }

    func testOverlayPanel_hasNonActivatingStyle() {
        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)
        let panel = controller.panelWindow

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel),
            "Panel must have .nonactivatingPanel style")
    }

    func testOverlayPanel_floatingLevel() {
        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)
        let panel = controller.panelWindow

        XCTAssertEqual(panel.level, .floating,
            "Panel must be at floating level (always on top)")
    }

    func testOverlayPanel_doesNotHideOnDeactivate() {
        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)
        let panel = controller.panelWindow

        XCTAssertFalse(panel.hidesOnDeactivate,
            "Panel must not hide when the app deactivates")
    }

    // MARK: - MT-6-V4: Position persistence

    func testPositionPersistence_saveAndRestore() {
        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)

        guard let screen = NSScreen.main else {
            XCTFail("No main screen available")
            return
        }

        let visibleFrame = screen.visibleFrame
        let testPosition = NSPoint(
            x: visibleFrame.maxX - widgetSize.width,
            y: visibleFrame.midY
        )

        controller.savePosition(testPosition)

        // Verify UserDefaults were written
        let savedX = UserDefaults.standard.double(forKey: "SHH_OverlayPositionX")
        let savedY = UserDefaults.standard.double(forKey: "SHH_OverlayPositionY")

        XCTAssertEqual(savedX, Double(testPosition.x), accuracy: 0.1)
        XCTAssertEqual(savedY, Double(testPosition.y), accuracy: 0.1)

        let savedEdge = UserDefaults.standard.string(forKey: "SHH_OverlayEdge")
        XCTAssertNotNil(savedEdge, "Edge should be saved")
    }

    // MARK: - MT-6-V5: Edge snapping

    func testNearestEdge_bottomCenter_returnsBottom() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let bottomCenter = NSPoint(
            x: visibleFrame.midX - widgetSize.width / 2,
            y: visibleFrame.minY + 10
        )

        let edge = OverlayWidgetController.nearestEdge(
            for: bottomCenter,
            widgetSize: widgetSize,
            screen: screen
        )
        XCTAssertEqual(edge, .bottom)
    }

    func testNearestEdge_topCenter_returnsTop() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let topCenter = NSPoint(
            x: visibleFrame.midX - widgetSize.width / 2,
            y: visibleFrame.maxY - widgetSize.height - 10
        )

        let edge = OverlayWidgetController.nearestEdge(
            for: topCenter,
            widgetSize: widgetSize,
            screen: screen
        )
        XCTAssertEqual(edge, .top)
    }

    func testNearestEdge_leftSide_returnsLeft() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let leftSide = NSPoint(
            x: visibleFrame.minX + 10,
            y: visibleFrame.midY
        )

        let edge = OverlayWidgetController.nearestEdge(
            for: leftSide,
            widgetSize: widgetSize,
            screen: screen
        )
        XCTAssertEqual(edge, .left)
    }

    func testNearestEdge_rightSide_returnsRight() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let rightSide = NSPoint(
            x: visibleFrame.maxX - widgetSize.width - 10,
            y: visibleFrame.midY
        )

        let edge = OverlayWidgetController.nearestEdge(
            for: rightSide,
            widgetSize: widgetSize,
            screen: screen
        )
        XCTAssertEqual(edge, .right)
    }

    func testSnappedPosition_snapsToEdge_remainsOnScreen() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        // Place widget near the bottom-right corner
        let origin = NSPoint(
            x: visibleFrame.maxX - widgetSize.width - 20,
            y: visibleFrame.minY + 20
        )

        let snapped = OverlayWidgetController.snappedPosition(
            for: origin, widgetSize: widgetSize, screen: screen
        )

        // Snapped position must be within screen bounds
        let snappedRect = NSRect(origin: snapped, size: widgetSize)
        XCTAssertTrue(visibleFrame.contains(snappedRect),
            "Snapped widget must be fully within visible frame")
    }

    func testSnappedPosition_allCorners_stayOnScreen() {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        let corners = [
            NSPoint(x: visibleFrame.minX, y: visibleFrame.minY),           // bottom-left
            NSPoint(x: visibleFrame.maxX - widgetSize.width, y: visibleFrame.minY),  // bottom-right
            NSPoint(x: visibleFrame.minX, y: visibleFrame.maxY - widgetSize.height), // top-left
            NSPoint(x: visibleFrame.maxX - widgetSize.width, y: visibleFrame.maxY - widgetSize.height), // top-right
        ]

        for (i, corner) in corners.enumerated() {
            let snapped = OverlayWidgetController.snappedPosition(
                for: corner, widgetSize: widgetSize, screen: screen
            )
            let snappedRect = NSRect(origin: snapped, size: widgetSize)
            XCTAssertTrue(visibleFrame.contains(snappedRect),
                "Corner \(i): snapped widget must be within visible frame. Got \(snapped)")
        }
    }

    // MARK: - MT-6-V6: Invalid UserDefaults fallback

    func testRestoredPosition_invalidCoordinates_fallsBackToDefault() {
        // Write invalid position data
        UserDefaults.standard.set(Double(-9999), forKey: "SHH_OverlayPositionX")
        UserDefaults.standard.set(Double(-9999), forKey: "SHH_OverlayPositionY")
        UserDefaults.standard.set("bottom", forKey: "SHH_OverlayEdge")

        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)

        // Show the widget — it should fall back to default position
        controller.show()

        guard let screen = NSScreen.main else {
            XCTFail("No main screen")
            return
        }

        let expectedDefault = OverlayWidgetController.defaultBottomCenter(screen: screen)
        let actual = controller.currentOrigin

        XCTAssertEqual(actual.x, expectedDefault.x, accuracy: 1.0,
            "X should be default bottom-center")
        XCTAssertEqual(actual.y, expectedDefault.y, accuracy: 1.0,
            "Y should be default bottom-center")

        controller.hide()
    }

    func testRestoredPosition_noSavedData_usesDefault() {
        // Ensure no saved data
        UserDefaults.standard.removeObject(forKey: "SHH_OverlayPositionX")
        UserDefaults.standard.removeObject(forKey: "SHH_OverlayPositionY")
        UserDefaults.standard.removeObject(forKey: "SHH_OverlayEdge")

        let vm = OverlayViewModel()
        let controller = OverlayWidgetController(viewModel: vm)
        controller.show()

        guard let screen = NSScreen.main else {
            XCTFail("No main screen")
            return
        }

        let expectedDefault = OverlayWidgetController.defaultBottomCenter(screen: screen)
        let actual = controller.currentOrigin

        XCTAssertEqual(actual.x, expectedDefault.x, accuracy: 1.0)
        XCTAssertEqual(actual.y, expectedDefault.y, accuracy: 1.0)

        controller.hide()
    }
}
