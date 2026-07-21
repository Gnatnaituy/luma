import Foundation

struct AIRequestTarget {
    let provider: AIProviderConfiguration
    let model: AIModelConfiguration
    let apiKey: String
}

enum AIServiceError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Base URL 无效"
        case .invalidResponse:
            "AI 服务返回了无法识别的响应"
        case .requestFailed(let statusCode, let message):
            message.isEmpty ? "AI 请求失败（HTTP \(statusCode)）" : "AI 请求失败（HTTP \(statusCode)）：\(message)"
        case .emptyResponse:
            "AI 服务未返回文本"
        }
    }
}

struct AIService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func translate(
        text: String,
        targetLanguage: String,
        target: AIRequestTarget
    ) async throws -> String {
        let systemPrompt = "你是一名专业翻译。准确保留原文含义、格式、专有名词和换行，只输出翻译结果，不要解释。"
        let userPrompt = "请将以下内容翻译为\(targetLanguage)：\n\n\(text)"
        return try await send(systemPrompt: systemPrompt, userPrompt: userPrompt, target: target)
    }

    func testConnection(target: AIRequestTarget) async throws -> String {
        try await send(
            systemPrompt: "Reply with exactly OK.",
            userPrompt: "Connection test",
            target: target
        )
    }

    func send(systemPrompt: String, userPrompt: String, target: AIRequestTarget) async throws -> String {
        let request = try Self.makeRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            target: target
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw AIServiceError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: Self.errorMessage(from: data)
            )
        }
        return try Self.parseResponse(data, format: target.provider.apiFormat)
    }

    static func makeRequest(
        systemPrompt: String,
        userPrompt: String,
        target: AIRequestTarget
    ) throws -> URLRequest {
        guard let endpoint = endpoint(baseURL: target.provider.baseURL, format: target.provider.apiFormat) else {
            throw AIServiceError.invalidBaseURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any]
        switch target.provider.apiFormat {
        case .openAIChatCompletions:
            request.setValue("Bearer \(target.apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": target.model.name,
                "temperature": 0.2,
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ]
            ]
        case .anthropicMessages:
            request.setValue(target.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": target.model.name,
                "max_tokens": 4_096,
                "temperature": 0.2,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userPrompt]]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseResponse(_ data: Data, format: AIAPIFormat) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }
        let text: String?
        switch format {
        case .openAIChatCompletions:
            text = (object["choices"] as? [[String: Any]])?.first
                .flatMap { $0["message"] as? [String: Any] }?["content"] as? String
        case .anthropicMessages:
            let blocks = object["content"] as? [[String: Any]]
            text = blocks?
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        }
        let result = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !result.isEmpty else { throw AIServiceError.emptyResponse }
        return result
    }

    private static func endpoint(baseURL: String, format: AIAPIFormat) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix: String
        switch format {
        case .openAIChatCompletions:
            suffix = trimmed.hasSuffix("/chat/completions") ? "" : "/chat/completions"
        case .anthropicMessages:
            suffix = trimmed.hasSuffix("/v1/messages") ? "" : "/v1/messages"
        }
        return URL(string: trimmed + suffix)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data.prefix(500), encoding: .utf8) ?? ""
        }
        if let error = object["error"] as? [String: Any] {
            return error["message"] as? String ?? error["type"] as? String ?? ""
        }
        return object["message"] as? String ?? ""
    }
}
