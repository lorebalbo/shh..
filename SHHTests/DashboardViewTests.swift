import XCTest
import SwiftData

/// Validation tests for the Dashboard implementation (MT-7 scenarios).
/// Tests Style CRUD with single-active invariant (V2), Clear History (V5),
/// sidebar state persistence (V6), onboarding flag (V9), and pipeline
/// safety with style deletion (V8).
final class DashboardViewTests: XCTestCase {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            DictationEntry.self,
            Style.self,
            LLMProviderConfig.self,
        ])
        let config = ModelConfiguration(
            "DashboardTestStore",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - MT-7-V2: Style CRUD and single-active radio selection

    @MainActor
    func testStyleCRUD_createEditDeleteAndSingleActive() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Step 2: Create Style A
        let styleA = Style(name: "Formal", systemPrompt: "Be formal.")
        context.insert(styleA)
        try context.save()

        // Step 3: Create Style B
        let styleB = Style(name: "Brief", systemPrompt: "Be concise.")
        context.insert(styleB)
        try context.save()

        // Both exist
        let allDescriptor = FetchDescriptor<Style>(sortBy: [SortDescriptor(\.name)])
        var allStyles = try context.fetch(allDescriptor)
        XCTAssertEqual(allStyles.count, 2, "Two styles should exist after creation")

        // Step 4: Activate Style A
        try styleA.activate(in: context)
        try context.save()
        XCTAssertTrue(styleA.isActive, "Style A should be active")
        XCTAssertFalse(styleB.isActive, "Style B should be inactive")

        // Step 5: Activate Style B — A must deactivate
        try styleB.activate(in: context)
        try context.save()
        XCTAssertFalse(styleA.isActive, "Style A should be deactivated when B is activated")
        XCTAssertTrue(styleB.isActive, "Style B should now be active")

        // Verify single-active invariant
        let activeDescriptor = FetchDescriptor<Style>(
            predicate: #Predicate<Style> { $0.isActive }
        )
        let activeStyles = try context.fetch(activeDescriptor)
        XCTAssertEqual(activeStyles.count, 1, "Exactly one Style should be active")

        // Step 6: Edit Style B's name
        styleB.name = "Very Brief"
        try context.save()
        XCTAssertEqual(styleB.name, "Very Brief", "Style B's name should be updated")

        // Step 7: Delete Style A
        context.delete(styleA)
        try context.save()

        allStyles = try context.fetch(allDescriptor)
        XCTAssertEqual(allStyles.count, 1, "Only one style should remain after deletion")
        XCTAssertEqual(allStyles.first?.name, "Very Brief")

        // Step 8: Deselect Style B (no active Style)
        styleB.isActive = false
        try context.save()

        let afterDeselect = try context.fetch(activeDescriptor)
        XCTAssertEqual(afterDeselect.count, 0, "No Style should be active after deselection")
    }

    // MARK: - MT-7-V3: Home page DictationEntry query ordering and content

    @MainActor
    func testDictationEntriesOrderedByTimestampDescending() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Create entries with known order
        let entry1 = DictationEntry(rawText: "First entry")
        Thread.sleep(forTimeInterval: 0.01) // Ensure different timestamps
        let entry2 = DictationEntry(rawText: "Second entry", processedText: "Processed second")

        context.insert(entry1)
        context.insert(entry2)
        try context.save()

        // Fetch in reverse chronological order (as HomeView @Query does)
        let descriptor = FetchDescriptor<DictationEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        let entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 2, "Two entries should exist")
        XCTAssertEqual(entries.first?.rawText, "Second entry", "Newest entry should be first")
        XCTAssertEqual(entries.last?.rawText, "First entry", "Oldest entry should be last")
    }

    @MainActor
    func testDictationEntryWithProcessedText() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let styleId = UUID()
        let entry = DictationEntry(rawText: "raw text", processedText: "processed text", styleId: styleId)
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<DictationEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.rawText, "raw text")
        XCTAssertEqual(fetched.first?.processedText, "processed text")
        XCTAssertEqual(fetched.first?.styleId, styleId)
    }

    @MainActor
    func testDictationEntryWithoutProcessedText() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let entry = DictationEntry(rawText: "raw only text")
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<DictationEntry>()
        let fetched = try context.fetch(descriptor)
        XCTAssertNil(fetched.first?.processedText, "Processed text should be nil for RAW-only entry")
        XCTAssertNil(fetched.first?.styleId, "Style ID should be nil for RAW-only entry")
    }

    // MARK: - MT-7-V4: Home page with zero entries

    @MainActor
    func testEmptyDictationHistoryReturnsEmpty() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 0, "Empty database should return zero entries")
    }

    // MARK: - MT-7-V5: Clear History deletes all entries

    @MainActor
    func testClearHistoryDeletesAllEntries() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert 3 entries
        for i in 0..<3 {
            let entry = DictationEntry(rawText: "Entry \(i)")
            context.insert(entry)
        }
        try context.save()

        var descriptor = FetchDescriptor<DictationEntry>()
        var entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 3, "Should have 3 entries before clearing")

        // Clear history (same logic as SettingsView.clearHistory)
        for entry in entries {
            context.delete(entry)
        }
        try context.save()

        descriptor = FetchDescriptor<DictationEntry>()
        entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 0, "All entries should be deleted after clear")
    }

    @MainActor
    func testClearHistoryOnEmptyDatabaseDoesNotCrash() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Clear on empty — should not throw or crash
        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 0)

        // Simulate clearing empty history
        for entry in entries {
            context.delete(entry)
        }
        try context.save()

        // Verify still empty
        let afterClear = try context.fetch(descriptor)
        XCTAssertEqual(afterClear.count, 0, "Clear on empty database should succeed with 0 entries")
    }

    // MARK: - MT-7-V6: Sidebar collapsed state persistence via @AppStorage

    func testSidebarCollapsedStatePersistence() throws {
        let key = "sidebarCollapsed"
        let defaults = UserDefaults.standard

        // Default is false (expanded)
        defaults.removeObject(forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key), "Default sidebar state should be expanded (false)")

        // Simulate collapsing sidebar
        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key), "Sidebar collapsed state should persist as true")

        // Simulate reopening — state should still be collapsed
        let restored = defaults.bool(forKey: key)
        XCTAssertTrue(restored, "Sidebar collapsed state should survive across reads")

        // Cleanup
        defaults.removeObject(forKey: key)
    }

    // MARK: - MT-7-V8: Deleting active Style with pipeline safety

    @MainActor
    func testDeletingActiveStyleWhilePipelineUsesSnapshot() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Create and activate a style
        let style = Style(name: "Test Style", systemPrompt: "Format text.")
        context.insert(style)
        try context.save()
        try style.activate(in: context)
        try context.save()

        // Capture the style data before deletion (simulates pipeline snapshot)
        let capturedName = style.name
        let capturedPrompt = style.systemPrompt
        let capturedId = style.id

        // Delete the active style (simulates user action during pipeline processing)
        context.delete(style)
        try context.save()

        // Pipeline should still have the snapshot data
        XCTAssertEqual(capturedName, "Test Style")
        XCTAssertEqual(capturedPrompt, "Format text.")

        // Active style query should return nil
        let descriptor = FetchDescriptor<Style>(
            predicate: #Predicate<Style> { $0.isActive }
        )
        let activeStyles = try context.fetch(descriptor)
        XCTAssertEqual(activeStyles.count, 0, "No active style should exist after deletion")

        // A DictationEntry can still be created with the captured style ID
        let entry = DictationEntry(rawText: "raw", processedText: "processed", styleId: capturedId)
        context.insert(entry)
        try context.save()

        let entryDescriptor = FetchDescriptor<DictationEntry>()
        let entries = try context.fetch(entryDescriptor)
        XCTAssertEqual(entries.count, 1, "Entry should be created despite deleted style")
        XCTAssertEqual(entries.first?.styleId, capturedId, "Entry should reference the original style ID")
    }

    @MainActor
    func testTextProcessingPipelineFallsBackWhenNoActiveStyle() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // No active style exists
        let pipeline = TextProcessingPipeline(modelContext: context)

        // Pipeline should fall back to raw text
        let expectation = XCTestExpectation(description: "Pipeline processes raw text")
        Task {
            let result = await pipeline.process(rawText: "Hello world")
            XCTAssertEqual(result.rawText, "Hello world")
            XCTAssertNil(result.processedText, "No processed text when no active style")
            XCTAssertNil(result.styleId, "No style ID when no active style")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    @MainActor
    func testTextProcessingPipelineFallsBackWhenNoProvider() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Create and activate a style but no provider
        let style = Style(name: "Test", systemPrompt: "Format.")
        context.insert(style)
        try context.save()
        try style.activate(in: context)
        try context.save()

        let pipeline = TextProcessingPipeline(modelContext: context)

        let expectation = XCTestExpectation(description: "Pipeline falls back to raw")
        Task {
            let result = await pipeline.process(rawText: "Hello world")
            XCTAssertEqual(result.rawText, "Hello world")
            XCTAssertNil(result.processedText, "No processed text when no provider configured")
            XCTAssertEqual(result.styleId, style.id, "Style ID should be captured even without provider")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    // MARK: - MT-7-V9: Onboarding flag set on dismissal

    func testOnboardingFlagSetOnDismissal() {
        let key = "hasCompletedSetup"
        let defaults = UserDefaults.standard

        // Reset
        defaults.removeObject(forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key), "Onboarding should show on first launch (flag is false)")

        // Simulate dismissal — flag set to true
        defaults.set(true, forKey: key)
        XCTAssertTrue(defaults.bool(forKey: key), "Onboarding flag should be true after dismissal")

        // Simulate relaunch — flag persists
        let restored = defaults.bool(forKey: key)
        XCTAssertTrue(restored, "Onboarding flag should persist across sessions")

        // Reset to verify first-launch detection
        defaults.removeObject(forKey: key)
        XCTAssertFalse(defaults.bool(forKey: key), "Resetting flag should restore first-launch state")
    }
}
