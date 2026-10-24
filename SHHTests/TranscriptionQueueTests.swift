import AppKit
import XCTest

/// Tests for queued transcriptions: which recordings get auto-pasted, the
/// "N processing" label, and where its badge sits against the widget.
final class TranscriptionQueueTests: XCTestCase {

    private var queue: TranscriptionQueue!
    private var reportedCounts: [Int] = []

    override func setUp() {
        super.setUp()
        queue = TranscriptionQueue()
        reportedCounts = []
        queue.onPendingCountChange = { [unowned self] in self.reportedCounts.append($0) }
    }

    /// Records one utterance: start, then release (send for processing).
    private func record() -> Bool {
        queue.recordingDidStart()
        return queue.enqueue()
    }

    // MARK: - Auto-paste

    func testRecordingWithNothingInFlightIsPasted() {
        XCTAssertTrue(record())
    }

    func testRecordingStartedWhileAnotherIsProcessingIsNotPasted() {
        XCTAssertTrue(record())   // first: pasted when it finishes
        XCTAssertFalse(record())  // recorded while the first is processing
        XCTAssertFalse(record())  // and another
    }

    func testRecordingStaysQueuedEvenIfEarlierOnesFinishBeforeItStops() {
        _ = record()
        queue.recordingDidStart() // starts while the first is still processing
        queue.finish()            // first finishes mid-recording

        XCTAssertFalse(queue.enqueue())
    }

    func testOnceTheQueueDrainsTheNextRecordingIsPastedAgain() {
        _ = record()
        _ = record()
        queue.finish()
        queue.finish()

        XCTAssertTrue(record())
    }

    func testCancelledRecordingDoesNotAffectTheNextOne() {
        _ = record()
        queue.recordingDidStart() // queued recording, then cancelled: never enqueued
        queue.finish()

        XCTAssertTrue(record())
    }

    // MARK: - Pending count

    func testPendingCountTracksInFlightRecordings() {
        _ = record()
        _ = record()
        queue.finish()
        _ = record()
        queue.finish()
        queue.finish()

        XCTAssertEqual(reportedCounts, [1, 2, 1, 2, 1, 0])
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testExtraFinishIsIgnored() {
        queue.finish()

        XCTAssertEqual(queue.pendingCount, 0)
        XCTAssertEqual(reportedCounts, [])
    }

    // MARK: - "N processing" label

    func testLoneProcessingRecordingShowsOnlyTheSpinner() {
        XCTAssertNil(OverlayViewModel.queueLabel(processingCount: 0, isRecording: false))
        XCTAssertNil(OverlayViewModel.queueLabel(processingCount: 0, isRecording: true))
        XCTAssertNil(OverlayViewModel.queueLabel(processingCount: 1, isRecording: false))
    }

    func testRecordingOverAProcessingOneShowsTheLabel() {
        XCTAssertEqual(OverlayViewModel.queueLabel(processingCount: 1, isRecording: true), "1 processing")
    }

    func testSeveralProcessingShowTheLabel() {
        XCTAssertEqual(OverlayViewModel.queueLabel(processingCount: 2, isRecording: false), "2 processing")
        XCTAssertEqual(OverlayViewModel.queueLabel(processingCount: 3, isRecording: true), "3 processing")
    }

    func testViewModelDerivesProcessingStateFromTheCount() {
        let viewModel = OverlayViewModel()
        XCTAssertFalse(viewModel.isProcessing)

        viewModel.processingCount = 1
        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertNil(viewModel.queueLabel)

        viewModel.isRecording = true
        XCTAssertEqual(viewModel.queueLabel, "1 processing")
    }

    // MARK: - Badge placement

    private let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
    private let badgeSize = OverlayWidgetController.badgeSize
    private let widgetSize = OverlayWidgetController.widgetSize

    func testBadgeSitsBelowTheWidgetOnTheTopEdge() {
        let widget = NSRect(origin: NSPoint(x: 700, y: 949 - widgetSize.height), size: widgetSize)
        let origin = OverlayWidgetController.badgeOrigin(widgetFrame: widget, badgeSize: badgeSize, screenFrame: screenFrame)

        XCTAssertEqual(origin.y + badgeSize.height, widget.minY, accuracy: 0.1)
        XCTAssertEqual(origin.x + badgeSize.width / 2, widget.midX, accuracy: 0.1)
    }

    func testBadgeSitsBelowTheWidgetOverTheDock() {
        let widget = NSRect(origin: NSPoint(x: 1367, y: 89), size: widgetSize) // bottom edge, just above the Dock
        let origin = OverlayWidgetController.badgeOrigin(widgetFrame: widget, badgeSize: badgeSize, screenFrame: screenFrame)

        XCTAssertEqual(origin.y + badgeSize.height, widget.minY, accuracy: 0.1)
        XCTAssertEqual(origin.x + badgeSize.width / 2, widget.midX, accuracy: 0.1)
    }

    func testBadgeGoesAboveTheWidgetWhenBelowIsOffScreen() {
        let widget = NSRect(origin: NSPoint(x: 700, y: 4), size: widgetSize) // bottom edge, Dock hidden
        let origin = OverlayWidgetController.badgeOrigin(widgetFrame: widget, badgeSize: badgeSize, screenFrame: screenFrame)

        XCTAssertEqual(origin.y, widget.maxY, accuracy: 0.1)
        XCTAssertEqual(origin.x + badgeSize.width / 2, widget.midX, accuracy: 0.1)
    }
}
