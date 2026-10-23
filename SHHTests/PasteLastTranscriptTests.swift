import CoreGraphics
import SwiftData
import XCTest

/// Tests for the ⌃⌥⌘V paste-last-transcript shortcut: which key presses trigger it,
/// and which dictation's text it pastes.
final class PasteLastTranscriptTests: XCTestCase {

    // MARK: - Shortcut matching

    private let v: Int64 = 9
    private let controlOptionCommand: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    func testControlOptionCommandVIsTheShortcut() {
        XCTAssertTrue(GlobalInputManager.isPasteLastShortcut(keyCode: v, flags: controlOptionCommand))
    }

    func testCapsLockAndNonModifierFlagsDoNotMatter() {
        let flags = controlOptionCommand.union([.maskAlphaShift, .maskNonCoalesced])
        XCTAssertTrue(GlobalInputManager.isPasteLastShortcut(keyCode: v, flags: flags))
    }

    func testOtherModifierCombinationsAreLeftAlone() {
        let combinations: [CGEventFlags] = [
            [.maskCommand],                                       // paste
            [.maskCommand, .maskShift],                           // paste and match style in many apps
            [.maskCommand, .maskAlternate],                       // Finder: move item here
            [.maskCommand, .maskAlternate, .maskShift],           // paste and match style
            [.maskCommand, .maskControl],                         // Office: paste special
            controlOptionCommand.union(.maskShift),
            [],
        ]
        for flags in combinations {
            XCTAssertFalse(
                GlobalInputManager.isPasteLastShortcut(keyCode: v, flags: flags),
                "flags \(flags.rawValue) should not trigger the shortcut"
            )
        }
    }

    func testOtherKeysAreLeftAlone() {
        XCTAssertFalse(GlobalInputManager.isPasteLastShortcut(keyCode: 8, flags: controlOptionCommand)) // C
    }

    // MARK: - Last transcript

    /// Held for the test's duration: a ModelContext doesn't keep its container alive.
    private var container: ModelContainer?

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([DictationEntry.self, Style.self, LLMProviderConfig.self])
        let config = ModelConfiguration("PasteLastTests", schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    private func insert(_ rawText: String, processed: String? = nil, secondsAgo: TimeInterval, into context: ModelContext) {
        let entry = DictationEntry(rawText: rawText, processedText: processed)
        entry.timestamp = Date().addingTimeInterval(-secondsAgo)
        context.insert(entry)
    }

    @MainActor
    func testNothingToPasteWhenHistoryIsEmpty() throws {
        let context = try makeContext()
        XCTAssertNil(DictationEntry.lastPastableText(in: context))
    }

    @MainActor
    func testPastesTheMostRecentTranscript() throws {
        let context = try makeContext()
        insert("older", secondsAgo: 60, into: context)
        insert("newest", secondsAgo: 1, into: context)
        insert("middle", secondsAgo: 30, into: context)

        XCTAssertEqual(DictationEntry.lastPastableText(in: context), "newest")
    }

    @MainActor
    func testPastesTheStyledRewriteWhenAStyleWasUsed() throws {
        let context = try makeContext()
        insert("hey can you send me the file", processed: "Could you send me the file?", secondsAgo: 1, into: context)

        XCTAssertEqual(DictationEntry.lastPastableText(in: context), "Could you send me the file?")
    }

    @MainActor
    func testSkipsRecordingsWithoutATranscript() throws {
        let context = try makeContext()
        insert("the real one", secondsAgo: 60, into: context)
        insert(DictationEntry.noSpeechText, secondsAgo: 20, into: context)
        insert(DictationEntry.transcriptionErrorText, secondsAgo: 10, into: context)

        XCTAssertEqual(DictationEntry.lastPastableText(in: context), "the real one")
    }
}
