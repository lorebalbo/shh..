import Foundation
import SwiftData

/// Notification posted when the TextProcessingPipeline issues a warning
/// (e.g., no LLM configured, LLM request failed). The userInfo dictionary
/// contains "message" (String) describing the warning.
extension Notification.Name {
    static let shhWarning = Notification.Name("shhWarning")
}

/// Result of running RAW text through the text processing pipeline.
struct TextProcessingResult {
    let rawText: String
    let processedText: String?
    let styleId: UUID?
}

/// Processes RAW transcription text through the active Style's system prompt
/// via the configured LLM provider. Falls back to RAW text when no Style is
/// active, no provider is configured, or the LLM request fails.
final class TextProcessingPipeline {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Processes raw text through the active Style and LLM provider.
    /// - Parameter rawText: The transcribed text from the transcription pipeline.
    /// - Returns: A result containing RAW text, optional Processed text, and Style ID.
    func process(rawText: String) async -> TextProcessingResult {
        // Step 1: Check if a Style is active
        guard let activeStyle = fetchActiveStyle() else {
            return TextProcessingResult(rawText: rawText, processedText: nil, styleId: nil)
        }

        // Step 2: Check if an LLM provider is configured
        guard let activeProvider = fetchActiveProvider() else {
            postWarning("No LLM provider configured. Style \"\(activeStyle.name)\" was not applied. Configure a provider in Settings.")
            return TextProcessingResult(rawText: rawText, processedText: nil, styleId: activeStyle.id)
        }

        // Step 3: Skip LLM call for empty text
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return TextProcessingResult(rawText: rawText, processedText: nil, styleId: activeStyle.id)
        }

        // Step 4: Build the appropriate LLM client and send the request
        let provider = buildProvider(from: activeProvider)

        PipelineEventLog.shared.append("Applying style \"\(activeStyle.name)\" via \(activeProvider.modelName)...", kind: .info)

        do {
            let processedText = try await provider.complete(
                systemPrompt: activeStyle.systemPrompt,
                userMessage: rawText
            )
            PipelineEventLog.shared.append("Style applied successfully by \(activeProvider.modelName).", kind: .success)
            return TextProcessingResult(rawText: rawText, processedText: processedText, styleId: activeStyle.id)
        } catch {
            let description = (error as? LLMError)?.localizedDescription ?? error.localizedDescription
            postWarning("LLM processing failed: \(description). Falling back to raw text.")
            PipelineEventLog.shared.append("LLM processing failed: \(description)", kind: .error)
            return TextProcessingResult(rawText: rawText, processedText: nil, styleId: activeStyle.id)
        }
    }

    // MARK: - Private

    private func fetchActiveStyle() -> Style? {
        let descriptor = FetchDescriptor<Style>(
            predicate: #Predicate<Style> { $0.isActive }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchActiveProvider() -> LLMProviderConfig? {
        let descriptor = FetchDescriptor<LLMProviderConfig>(
            predicate: #Predicate<LLMProviderConfig> { $0.isActive }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func buildProvider(from config: LLMProviderConfig) -> LLMProvider {
        switch config.providerType {
        case .anthropic:
            return AnthropicAdapter(
                baseURL: config.endpointURL.isEmpty ? "https://api.anthropic.com" : config.endpointURL,
                apiKey: config.apiKey,
                modelName: config.modelName
            )
        case .openAI:
            return LLMClient(
                baseURL: config.endpointURL.isEmpty ? "https://api.openai.com" : config.endpointURL,
                apiKey: config.apiKey,
                modelName: config.modelName
            )
        case .local:
            return LLMClient(
                baseURL: config.endpointURL,
                apiKey: config.apiKey,
                modelName: config.modelName
            )
        }
    }

    private func postWarning(_ message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .shhWarning,
                object: nil,
                userInfo: ["message": message]
            )
        }
    }
}
