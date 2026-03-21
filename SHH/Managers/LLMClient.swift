import Foundation

// MARK: - Common Types

/// Errors that can occur during LLM provider communication.
enum LLMError: Error, LocalizedError {
    case networkError(Error)
    case authenticationError
    case timeout
    case invalidResponse(String)
    case rateLimited
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .authenticationError:
            return "Authentication failed — check your API key"
        case .timeout:
            return "Request timed out"
        case .invalidResponse(let detail):
            return "Invalid response from LLM provider: \(detail)"
        case .rateLimited:
            return "Rate limited by LLM provider — try again later"
        case .serverError(let code):
            return "LLM provider returned server error (\(code))"
        }
    }
}

/// Protocol for LLM providers. Both OpenAI-compatible and Anthropic clients conform.
protocol LLMProvider {
    func complete(systemPrompt: String, userMessage: String) async throws -> String
}

// MARK: - OpenAI-Compatible Client

/// Sends non-streaming POST requests to the /v1/chat/completions endpoint.
/// Works with OpenAI, local LLM servers (LM Studio, Ollama), and any
/// OpenAI-compatible API.
final class LLMClient: LLMProvider {
    let baseURL: String
    let apiKey: String
    let modelName: String

    private let session: URLSession

    init(baseURL: String, apiKey: String = "", modelName: String) {
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

        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body = OpenAIChatRequest(
            model: modelName,
            messages: [
                .init(role: "system", content: systemPrompt),
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
        return try parseOpenAIResponse(data)
    }

    // MARK: - Private

    private func buildURL() throws -> URL {
        let endpoint = baseURL.hasSuffix("/")
            ? "\(baseURL)v1/chat/completions"
            : "\(baseURL)/v1/chat/completions"
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

    private func parseOpenAIResponse(_ data: Data) throws -> String {
        let decoded: OpenAIChatResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        } catch {
            throw LLMError.invalidResponse("Failed to decode response: \(error.localizedDescription)")
        }

        guard let choice = decoded.choices.first,
              !choice.message.content.isEmpty
        else {
            throw LLMError.invalidResponse("No content in response choices")
        }

        return choice.message.content
    }
}

// MARK: - OpenAI Request/Response Types

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
