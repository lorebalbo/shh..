import Foundation
import SwiftData

enum LLMProviderType: String, Codable {
    case openAI
    case anthropic
    case local
}

@Model
final class LLMProviderConfig {
    @Attribute(.unique) var id: UUID
    var providerType: LLMProviderType
    var apiKey: String
    var endpointURL: String
    var modelName: String
    var isActive: Bool

    init(
        providerType: LLMProviderType,
        apiKey: String = "",
        endpointURL: String = "",
        modelName: String = "",
        isActive: Bool = false
    ) {
        self.id = UUID()
        self.providerType = providerType
        self.apiKey = apiKey
        self.endpointURL = endpointURL
        self.modelName = modelName
        self.isActive = isActive
    }

    /// Activates this config, deactivating all others to enforce
    /// the single-active-provider invariant.
    func activate(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<LLMProviderConfig>(
            predicate: #Predicate<LLMProviderConfig> { $0.isActive }
        )
        let activeConfigs = try context.fetch(descriptor)
        for config in activeConfigs {
            config.isActive = false
        }
        self.isActive = true
    }
}
