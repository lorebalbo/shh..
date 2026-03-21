import Foundation

/// Adapter that conforms to LLMProvider but translates requests to Anthropic's
/// Messages API format (/v1/messages).
///
/// Maps the system prompt to the top-level "system" parameter, user messages
/// to the "content" array, and sets the required x-api-key and
/// anthropic-version headers.
final class AnthropicAdapter: LLMProvider {
    let baseURL: String
    let apiKey: String
    let modelName: String

    private static let anthropicVersion = "2023-06-01"

    private let session: URLSession

    init(baseURL: String = "https://api.anthropic.com", apiKey: String, modelName: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    func complete(systemPrompt: String, userMessage: String) async throws -> String {
        let url = try buildURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body = AnthropicMessagesRequest(
            model: modelName,
            max_tokens: 4096,
            system: systemPrompt,
            messages: [
                .init(role: "user", content: userMessage),
            ]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.timeout
        } catch {
            throw LLMError.networkError(error)
        }

        try validateHTTPResponse(response)
        return try parseAnthropicResponse(data)
    }

    // MARK: - Private

    private func buildURL() throws -> URL {
        let endpoint = baseURL.hasSuffix("/")
            ? "\(baseURL)v1/messages"
            : "\(baseURL)/v1/messages"
        guard let url = URL(string: endpoint) else {
            throw LLMError.invalidResponse("Invalid base URL: \(baseURL)")
        }
        return url
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Non-HTTP response received")
        }
        switch httpResponse.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw LLMError.authenticationError
        case 429:
            throw LLMError.rateLimited
        case 500...599:
            throw LLMError.serverError(httpResponse.statusCode)
        default:
            throw LLMError.invalidResponse("HTTP \(httpResponse.statusCode)")
        }
    }

    private func parseAnthropicResponse(_ data: Data) throws -> String {
        let decoded: AnthropicMessagesResponse
        do {
            decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse("Failed to decode Anthropic response: \(error.localizedDescription)")
        }

        guard let textBlock = decoded.content.first(where: { $0.type == "text" }),
              !textBlock.text.isEmpty
        else {
            throw LLMError.invalidResponse("No text content in Anthropic response")
        }

        return textBlock.text
    }
}

// MARK: - Anthropic Request/Response Types

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
}
