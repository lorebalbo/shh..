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

        PipelineEventLog.shared.append("→ POST \(url.absoluteString) [model: \(modelName)]", kind: .info)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            PipelineEventLog.shared.append("❌ Request timed out — \(url.absoluteString)", kind: .error)
            throw LLMError.timeout
        } catch {
            PipelineEventLog.shared.append("❌ Network error: \(error.localizedDescription)", kind: .error)
            throw LLMError.networkError(error)
        }

        if let http = response as? HTTPURLResponse {
            PipelineEventLog.shared.append("← HTTP \(http.statusCode) from \(url.host ?? url.absoluteString)", kind: http.statusCode < 300 ? .info : .error)
        }

        try validateHTTPResponse(response)
        return try parseOpenAIResponse(data, url: url)
    }

    // MARK: - Private

    private func buildURL() throws -> URL {
        // Normalize: strip trailing slashes and any trailing /v1 (or /v1/)
        // so that users pasting "http://localhost:1234/v1" don't get /v1/v1/...
        var base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if base.hasSuffix("/v1") {
            base = String(base.dropLast(3))
        }
        let endpoint = "\(base)/v1/chat/completions"
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

    private func parseOpenAIResponse(_ data: Data, url: URL) throws -> String {
        let decoded: OpenAIChatResponse
        do {
            decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        } catch {
            // Log up to 500 chars of the raw body so the user can see what the server returned
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
            let preview = String(rawBody.prefix(500))
            PipelineEventLog.shared.append("❌ Decode error: \(error.localizedDescription)", kind: .error)
            PipelineEventLog.shared.append("   Raw body: \(preview)", kind: .error)
            throw LLMError.invalidResponse("Failed to decode response: \(error.localizedDescription)")
        }

        guard let choice = decoded.choices.first,
              let content = choice.message.content,
              !content.isEmpty
        else {
            let rawBody = String(data: data, encoding: .utf8).map { String($0.prefix(300)) } ?? "<non-UTF8>"
            PipelineEventLog.shared.append("❌ No content in response — raw: \(rawBody)", kind: .error)
            throw LLMError.invalidResponse("No content in response choices")
        }

        return content
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
        let content: String?
    }
}
