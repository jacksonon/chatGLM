import Foundation

enum ZhipuAPIError: Error {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
}

extension ZhipuAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置智谱 API Key。请在 Xcode 的 Scheme 中设置环境变量 ZHIPU_API_KEY。"
        case .invalidResponse:
            return "服务器响应无效，请稍后重试。"
        case let .httpError(statusCode, body):
            if let body, !body.isEmpty {
                let snippet = body.count > 300 ? String(body.prefix(300)) + "…" : body
                return "服务器返回错误（\(statusCode)）: \(snippet)"
            } else {
                return "服务器返回错误（\(statusCode)）。"
            }
        }
    }
}

final class ZhipuAPIClient {
    static let shared = ZhipuAPIClient()

    private let urlSession: URLSession
    private let baseURL: URL
    private let apiKeyProvider: () -> String

    init(
        baseURL: URL = URL(string: "https://open.bigmodel.cn")!,
        urlSession: URLSession = .shared,
        apiKeyProvider: @escaping () -> String = {
            ProcessInfo.processInfo.environment["ZHIPU_API_KEY"] ?? ""
        }
    ) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.apiKeyProvider = apiKeyProvider
    }

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method

        let key = apiKeyProvider()
        guard !key.isEmpty else {
            throw ZhipuAPIError.missingAPIKey
        }

        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: "POST")

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZhipuAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let bodyText = String(data: data, encoding: .utf8)
            throw ZhipuAPIError.httpError(statusCode: httpResponse.statusCode, body: bodyText)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: data)
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        let request = try makeRequest(path: path, method: "GET")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZhipuAPIError.invalidResponse
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            let bodyText = String(data: data, encoding: .utf8)
            throw ZhipuAPIError.httpError(statusCode: httpResponse.statusCode, body: bodyText)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: - Chat

    func createAsyncChatCompletion(request: ZhipuAsyncChatRequest) async throws -> ZhipuAsyncTaskResponse {
        try await send(path: "api/paas/v4/async/chat/completions", body: request)
    }

    // MARK: - Video

    func createVideoGeneration(request: ZhipuVideoGenerationRequest) async throws -> ZhipuAsyncTaskResponse {
        try await send(path: "api/paas/v4/videos/generations", body: request)
    }

    // MARK: - Image

    func createImageGeneration(request: ZhipuImageGenerationRequest) async throws -> ZhipuImageGenerationResponse {
        try await send(path: "api/paas/v4/images/generations", body: request)
    }

    // MARK: - Async result

    func fetchAsyncResult(id: String) async throws -> ZhipuAsyncResultResponse {
        try await get(path: "api/paas/v4/async-result/\(id)")
    }
}
