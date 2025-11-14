import Foundation
import Alamofire

enum ZhipuAPIError: Error {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
}

extension ZhipuAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置智谱 API Key。请在设置中填写，或在 Xcode 的 Scheme 中设置环境变量 ZHIPU_API_KEY。"
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

    private let session: Session
    private let baseURL: URL
    private let apiKeyProvider: () -> String

    init(
        baseURL: URL = URL(string: "https://open.bigmodel.cn")!,
        session: Session = .default,
        apiKeyProvider: @escaping () -> String = {
            if let stored = UserDefaults.standard.string(forKey: "ZhipuAPIKey"), !stored.isEmpty {
                return stored
            }
            return ProcessInfo.processInfo.environment["ZHIPU_API_KEY"] ?? ""
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.apiKeyProvider = apiKeyProvider
    }

    private func headers() throws -> HTTPHeaders {
        let key = apiKeyProvider()
        guard !key.isEmpty else {
            throw ZhipuAPIError.missingAPIKey
        }
        var headers: HTTPHeaders = [
            "Authorization": "Bearer \(key)"
        ]
        headers.add(.contentType("application/json"))
        return headers
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        let headers = try headers()

        let request = session.request(
            url,
            method: .post,
            parameters: body,
            encoder: JSONParameterEncoder.default,
            headers: headers
        )

        let response = await request.serializingDecodable(Response.self).response
        guard let statusCode = response.response?.statusCode else {
            throw ZhipuAPIError.invalidResponse
        }
#if DEBUG
        print("[ZhipuAPI] POST \(path) status=\(statusCode)")
#endif

        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            let bodyText = response.data.flatMap { String(data: $0, encoding: .utf8) }
#if DEBUG
            if let bodyText {
                print("[ZhipuAPI] POST \(path) error body: \(bodyText)")
            }
#endif
            if let afError = error.asAFError, let code = afError.responseCode {
                throw ZhipuAPIError.httpError(statusCode: code, body: bodyText)
            } else {
                throw error
            }
        }
    }

    private func get<Response: Decodable>(path: String) async throws -> Response {
        let url = baseURL.appendingPathComponent(path)
        let headers = try headers()

        let request = session.request(url, method: .get, headers: headers)
        let response = await request.serializingDecodable(Response.self).response
        guard let statusCode = response.response?.statusCode else {
            throw ZhipuAPIError.invalidResponse
        }
#if DEBUG
        print("[ZhipuAPI] GET \(path) status=\(statusCode)")
#endif

        switch response.result {
        case .success(let value):
            return value
        case .failure(let error):
            let bodyText = response.data.flatMap { String(data: $0, encoding: .utf8) }
#if DEBUG
            if let bodyText {
                print("[ZhipuAPI] GET \(path) error body: \(bodyText)")
            }
#endif
            if let afError = error.asAFError, let code = afError.responseCode {
                throw ZhipuAPIError.httpError(statusCode: code, body: bodyText)
            } else {
                throw error
            }
        }
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

    // MARK: - Streaming chat via SSE

    func streamChatCompletion(request: ZhipuAsyncChatRequest) -> AsyncThrowingStream<ZhipuStreamResponse, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("api/paas/v4/chat/completions")
                    let key = apiKeyProvider()
                    guard !key.isEmpty else {
                        throw ZhipuAPIError.missingAPIKey
                    }

                    var urlRequest = URLRequest(url: url)
                    urlRequest.httpMethod = "POST"
                    urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    urlRequest.httpBody = try JSONEncoder().encode(request)

                    var buffer = ""
                    let dataRequest = session.streamRequest(urlRequest)

                    dataRequest.responseStreamString { stream in
                        switch stream.event {
                        case .stream(let result):
                            switch result {
                            case .success(let chunk):
                                buffer.append(chunk)
                                self.processBuffer(&buffer, continuation: continuation)
                            case .failure(let error):
                                continuation.finish(throwing: error)
                            }
                        case .complete(let completion):
                            if let error = completion.error {
                                continuation.finish(throwing: error)
                            } else {
                                continuation.finish()
                            }
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func processBuffer(_ buffer: inout String, continuation: AsyncThrowingStream<ZhipuStreamResponse, Error>.Continuation) {
        let decoder = JSONDecoder()

        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)

            if line.isEmpty || line.hasPrefix(":") { continue }
            guard line.hasPrefix("data:") else { continue }

            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                continuation.finish()
                break
            }
            guard !payload.isEmpty else { continue }

            do {
                let chunk = try decoder.decode(ZhipuStreamResponse.self, from: Data(payload.utf8))
                continuation.yield(chunk)
            } catch {
#if DEBUG
                print("[ZhipuAPI] stream decode error:", error)
#endif
            }
        }
    }
}
