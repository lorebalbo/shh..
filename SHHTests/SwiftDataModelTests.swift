import XCTest
import SwiftData

/// Validation tests for SwiftData model invariants (MT-1 scenarios V4, V5, V6, V7).
/// Models are compiled directly into the test target (not using @testable import).
final class SwiftDataModelTests: XCTestCase {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            DictationEntry.self,
            Style.self,
            LLMProviderConfig.self,
        ])
        let config = ModelConfiguration(
            "TestStore",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - MT-1-V4: Only one Style can be active at a time

    @MainActor
    func testActivatingStyleDeactivatesOthers() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let styleA = Style(name: "Formal", systemPrompt: "Be formal.")
        let styleB = Style(name: "Casual", systemPrompt: "Be casual.")
        context.insert(styleA)
        context.insert(styleB)
        try context.save()

        // Activate A
        try styleA.activate(in: context)
        try context.save()
        XCTAssertTrue(styleA.isActive, "Style A should be active after activation")
        XCTAssertFalse(styleB.isActive, "Style B should be inactive")

        // Activate B — A must lose active status
        try styleB.activate(in: context)
        try context.save()
        XCTAssertFalse(styleA.isActive, "Style A should be deactivated when B is activated")
        XCTAssertTrue(styleB.isActive, "Style B should now be active")

        // Verify exactly one active
        let descriptor = FetchDescriptor<Style>(
            predicate: #Predicate<Style> { $0.isActive }
        )
        let activeStyles = try context.fetch(descriptor)
        XCTAssertEqual(activeStyles.count, 1, "Exactly one Style should be active")
        XCTAssertEqual(activeStyles.first?.name, "Casual")
    }

    // MARK: - MT-1-V5: Only one LLMProviderConfig can be active at a time

    @MainActor
    func testActivatingLLMConfigDeactivatesOthers() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let configA = LLMProviderConfig(
            providerType: .openAI,
            apiKey: "sk-test1",
            modelName: "gpt-4"
        )
        let configB = LLMProviderConfig(
            providerType: .local,
            endpointURL: "http://localhost:1234/v1",
            modelName: "test-model"
        )
        context.insert(configA)
        context.insert(configB)
        try context.save()

        // Activate A
        try configA.activate(in: context)
        try context.save()
        XCTAssertTrue(configA.isActive, "Config A should be active after activation")
        XCTAssertFalse(configB.isActive, "Config B should be inactive")

        // Activate B — A must lose active status
        try configB.activate(in: context)
        try context.save()
        XCTAssertFalse(configA.isActive, "Config A should be deactivated when B is activated")
        XCTAssertTrue(configB.isActive, "Config B should now be active")

        // Verify exactly one active
        let descriptor = FetchDescriptor<LLMProviderConfig>(
            predicate: #Predicate<LLMProviderConfig> { $0.isActive }
        )
        let activeConfigs = try context.fetch(descriptor)
        XCTAssertEqual(activeConfigs.count, 1, "Exactly one LLMProviderConfig should be active")
        XCTAssertEqual(activeConfigs.first?.providerType, .local)
    }

    // MARK: - MT-1-V6: Rapid toggling of active Style does not corrupt invariant

    @MainActor
    func testRapidStyleTogglePreservesInvariant() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let styles = (0..<5).map { i in
            Style(name: "Style \(Character(UnicodeScalar(65 + i)!))", systemPrompt: "Prompt \(i)")
        }
        for style in styles {
            context.insert(style)
        }
        try context.save()

        // Rapidly activate each in sequence
        for style in styles {
            try style.activate(in: context)
            try context.save()
        }

        // Only the last (E) should be active
        let descriptor = FetchDescriptor<Style>(
            predicate: #Predicate<Style> { $0.isActive }
        )
        let activeStyles = try context.fetch(descriptor)
        XCTAssertEqual(activeStyles.count, 1, "Exactly one Style should be active after rapid toggling")
        XCTAssertEqual(activeStyles.first?.name, "Style E", "The last activated style (E) should be active")

        // Verify all others are inactive
        let allDescriptor = FetchDescriptor<Style>()
        let allStyles = try context.fetch(allDescriptor)
        XCTAssertEqual(allStyles.count, 5, "All 5 styles should still exist (no duplicates)")
        let inactiveCount = allStyles.filter { !$0.isActive }.count
        XCTAssertEqual(inactiveCount, 4, "Exactly 4 styles should be inactive")
    }

    // MARK: - MT-1-V7: Deleting the active LLMProviderConfig leaves no phantom active provider

    @MainActor
    func testDeletingActiveLLMConfigLeavesNoActiveProvider() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let config = LLMProviderConfig(
            providerType: .local,
            endpointURL: "http://localhost:1234/v1",
            modelName: "test-model"
        )
        context.insert(config)
        try context.save()

        // Activate then delete
        try config.activate(in: context)
        try context.save()
        XCTAssertTrue(config.isActive)

        context.delete(config)
        try context.save()

        // Query active — should return nil/empty
        let descriptor = FetchDescriptor<LLMProviderConfig>(
            predicate: #Predicate<LLMProviderConfig> { $0.isActive }
        )
        let activeConfigs = try context.fetch(descriptor)
        XCTAssertEqual(activeConfigs.count, 0, "No active LLMProviderConfig should exist after deletion")

        // Query all — should be empty
        let allDescriptor = FetchDescriptor<LLMProviderConfig>()
        let allConfigs = try context.fetch(allDescriptor)
        XCTAssertEqual(allConfigs.count, 0, "No LLMProviderConfig should exist after deletion")
    }

    // MARK: - Additional: DictationEntry persistence

    @MainActor
    func testDictationEntryPersistence() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let entry = DictationEntry(rawText: "Hello world", processedText: "Hello, world.")
        context.insert(entry)
        try context.save()

        let descriptor = FetchDescriptor<DictationEntry>()
        let entries = try context.fetch(descriptor)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.rawText, "Hello world")
        XCTAssertEqual(entries.first?.processedText, "Hello, world.")
    }
}
