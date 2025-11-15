import Foundation
import Combine
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class ChatViewModel: ObservableObject {
    static let shared = ChatViewModel()

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var mode: ChatMode = .chat
    @Published var isSending: Bool = false
    @Published var selectedImageData: Data?
    @Published var selectedFileSummary: String?
    @Published var selectedFileName: String?
    @Published var selectedFileURL: URL?

    private let apiClient: ZhipuAPIClient
    private let enableStreamingChat = true
    private var currentTask: Task<Void, Never>?

    init(apiClient: ZhipuAPIClient? = nil) {
        self.apiClient = apiClient ?? ZhipuAPIClient.shared
    }

    func sendCurrentInput() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || selectedImageData != nil || selectedFileSummary != nil else {
            return
        }

        let userMessage = ChatMessage(
            sender: .user,
            text: trimmed,
            attachedImageData: selectedImageData,
            attachedFileName: selectedFileName
        )
        messages.append(userMessage)
        inputText = ""

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.send(for: userMessage)
        }
    }

    /// 专用于全局快捷输入面板，避免与主输入框状态产生耦合。
    func sendFromQuickInputPanel(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        // 防止因快捷输入面板的重复触发导致立刻出现两条完全相同的用户消息。
        if let last = messages.last,
           last.sender == .user,
           last.text == trimmed {
            return
        }

        let userMessage = ChatMessage(
            sender: .user,
            text: trimmed
        )
        messages.append(userMessage)

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            await self?.send(for: userMessage)
        }
    }

    func cancelCurrentRequest() {
        currentTask?.cancel()
    }

    private func send(for userMessage: ChatMessage) async {
        isSending = true
        defer {
            isSending = false
            selectedImageData = nil
            selectedFileSummary = nil
            selectedFileName = nil
            selectedFileURL = nil
            currentTask = nil
        }

        do {
            switch mode {
            case .chat:
                try await handleChat(userMessage: userMessage)
            case .image:
                try await handleImageGeneration(userMessage: userMessage)
            case .video:
                try await handleVideoGeneration(userMessage: userMessage)
            }
        } catch is CancellationError {
            print("[ChatViewModel] request cancelled")
        } catch {
            print("[ChatViewModel] send error:", error.localizedDescription)
        }
    }

    private func handleChat(userMessage: ChatMessage) async throws {
        let contextDescription = imageContextDescription(for: userMessage.attachedImageData)
        let fileContext = selectedFileSummary
        var content: String
        if let contextDescription {
            content = "\(userMessage.text)\n\n附加图像信息：\(contextDescription)"
        } else {
            content = userMessage.text
        }

        if let fileContext {
            let fileNamePart = selectedFileName ?? "选中文件"
            var extra = "\n\n附加文件（\(fileNamePart)）内容摘要：\(fileContext)"
            if let url = selectedFileURL {
                extra.append("\n文件路径：\(url.path)")
            }
            content.append(extra)
        }

        let historyMessages = messagesBefore(userMessage: userMessage).map {
            ZhipuChatMessage(
                role: $0.sender == .user ? "user" : "assistant",
                content: $0.text
            )
        }
        var apiMessages = historyMessages
        apiMessages.append(ZhipuChatMessage(role: "user", content: content))

        let request = ZhipuAsyncChatRequest(
            model: .glm45Flash,
            messages: apiMessages,
            temperature: 0.9,
            maxTokens: 1024
        )

        let placeholder = ChatMessage(
            sender: .assistant,
            text: "",
            isStreaming: true,
            isLoadingPending: false
        )
        messages.append(placeholder)
        try Task.checkCancellation()

        try Task.checkCancellation()

        if enableStreamingChat {
            do {
                try await streamChat(apiMessages: apiMessages, placeholderId: placeholder.id)
                return
            } catch is CancellationError {
                updateMessage(id: placeholder.id) { message in
                    message.text = "请求已取消"
                    message.isStreaming = false
                    message.isLoadingPending = false
                }
                throw CancellationError()
            } catch {
                print("[ChatViewModel] streaming chat fallback due to error:", error.localizedDescription)
                updateMessage(id: placeholder.id) { message in
                    message.text = ""
                    message.isStreaming = true
                    message.reasoning = nil
                    message.isLoadingPending = false
                }
            }
        }

        do {
            print("[ChatViewModel] start chat request, messages=\(apiMessages.count)")
            let asyncTask = try await apiClient.createAsyncChatCompletion(request: request)
            print("[ChatViewModel] async chat task id=\(asyncTask.id) status=\(asyncTask.taskStatus)")

            let result = try await waitForAsyncResult(taskId: asyncTask.id, expectingVideo: false)
            if let reasoning = result.choices?.first?.message?.reasoningContent,
               !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updateMessage(id: placeholder.id) { message in
                    message.reasoning = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            let fullText = result.choices?.first?.message?.content ?? ""
            print("[ChatViewModel] chat result text prefix=", fullText.prefix(120))
            try await animateStreamingReply(fullText: fullText, for: placeholder.id)
        } catch is CancellationError {
            updateMessage(id: placeholder.id) { message in
                message.text = "请求已取消"
                message.isStreaming = false
                message.isLoadingPending = false
            }
            throw CancellationError()
        } catch {
            let messageText = friendlyErrorMessage(error)
            print("[ChatViewModel] chat error:", messageText)
            updateMessage(id: placeholder.id) { message in
                message.text = messageText
                message.isStreaming = false
                message.isLoadingPending = false
            }
        }
    }

    private func handleImageGeneration(userMessage: ChatMessage) async throws {
        let request = ZhipuImageGenerationRequest(
            model: .cogview3Flash,
            prompt: userMessage.text,
            size: "1024x1024"
        )

        let placeholder = ChatMessage(
            sender: .assistant,
            text: "",
            isStreaming: true,
            isLoadingPending: true
        )
        messages.append(placeholder)
        try Task.checkCancellation()

        do {
            print("[ChatViewModel] start image generation prompt=\(userMessage.text)")
            let response = try await apiClient.createImageGeneration(request: request)
            let urls = response.data.compactMap { URL(string: $0.url) }
            print("[ChatViewModel] image generation urls count=\(urls.count)")
            updateMessage(id: placeholder.id) { message in
                message.text = urls.isEmpty ? "图片生成完成（无可用链接）" : "图片已生成"
                message.imageURLs = urls
                message.isStreaming = false
                message.isLoadingPending = false
            }
        } catch is CancellationError {
            updateMessage(id: placeholder.id) { message in
                message.text = "图片生成已取消"
                message.isStreaming = false
                message.isLoadingPending = false
            }
            throw CancellationError()
        } catch {
            let messageText = friendlyErrorMessage(error, prefix: "图片生成失败")
            print("[ChatViewModel] image generation error:", messageText)
            updateMessage(id: placeholder.id) { message in
                message.text = messageText
                message.isStreaming = false
                message.isLoadingPending = false
            }
        }
    }

    private func handleVideoGeneration(userMessage: ChatMessage) async throws {
        let request = ZhipuVideoGenerationRequest(
            model: .cogVideoXFlash,
            prompt: userMessage.text,
            quality: "quality",
            withAudio: true,
            size: "1920x1080",
            fps: 30
        )

        let placeholder = ChatMessage(
            sender: .assistant,
            text: "",
            isStreaming: true,
            isLoadingPending: true
        )
        messages.append(placeholder)

        do {
            print("[ChatViewModel] start video generation prompt=\(userMessage.text)")
            let asyncTask = try await apiClient.createVideoGeneration(request: request)
            print("[ChatViewModel] video generation task id=\(asyncTask.id) status=\(asyncTask.taskStatus)")
            let result = try await waitForAsyncResult(taskId: asyncTask.id, expectingVideo: true)
            let videoURL = result.videoResult?.first.flatMap { URL(string: $0.url) }
            if let videoURL {
                print("[ChatViewModel] video generation url=\(videoURL)")
            } else {
                print("[ChatViewModel] video generation completed without url")
            }

            updateMessage(id: placeholder.id) { message in
                message.text = videoURL == nil ? "视频生成完成" : ""
                message.videoURL = videoURL
                message.isStreaming = false
                message.isLoadingPending = false
            }
        } catch is CancellationError {
            updateMessage(id: placeholder.id) { message in
                message.text = "视频生成已取消"
                message.isStreaming = false
                message.isLoadingPending = false
            }
            throw CancellationError()
        } catch {
            let messageText = friendlyErrorMessage(error, prefix: "视频生成失败")
            updateMessage(id: placeholder.id) { message in
                message.text = messageText
                message.isStreaming = false
                message.isLoadingPending = false
            }
        }
    }

    private func messagesBefore(userMessage: ChatMessage) -> [ChatMessage] {
        guard let index = messages.firstIndex(of: userMessage) else {
            return []
        }
        return Array(messages[..<index])
    }

    private func imageContextDescription(for data: Data?) -> String? {
        guard let data else {
            return nil
        }

        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if let image = PlatformImage(data: data) {
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            return "一张分辨率约为 \(width)x\(height) 的图片。"
        }
        #elseif os(macOS)
        if let image = PlatformImage(data: data) {
            let size = image.size
            let width = Int(size.width)
            let height = Int(size.height)
            return "一张分辨率约为 \(width)x\(height) 的图片。"
        }
        #endif

        return "一张图片（无法解析尺寸）。"
    }

    private func updateMessage(id: UUID, _ update: (inout ChatMessage) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        var copy = messages[index]
        update(&copy)
        messages[index] = copy
    }

    private func animateStreamingReply(fullText: String, for id: UUID) async throws {
        var current = ""
        for character in fullText {
            try Task.checkCancellation()
            current.append(character)
            updateMessage(id: id) { message in
                message.text = current
                message.isStreaming = true
            }
            // 让 UI 有明显的“流式”效果
            await Task.yield()
            try await Task.sleep(nanoseconds: 70_000_000)
        }

        updateMessage(id: id) { message in
            message.isStreaming = false
        }
    }

    private func friendlyErrorMessage(_ error: Error, prefix: String = "请求失败") -> String {
        if let apiError = error as? ZhipuAPIError {
            return "\(prefix)：\(apiError.localizedDescription)"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "\(prefix)：无法解析智谱服务器域名，请检查当前网络或 DNS 设置。"
            case .notConnectedToInternet:
                return "\(prefix)：当前设备未连接网络，请检查网络后重试。"
            case .timedOut:
                return "\(prefix)：请求超时，请稍后重试。"
            default:
                break
            }
        }
        return "\(prefix)：\(error.localizedDescription)"
    }

    private func streamChat(apiMessages: [ZhipuChatMessage], placeholderId: UUID) async throws {
        let request = ZhipuAsyncChatRequest(
            model: .glm45Flash,
            messages: apiMessages,
            temperature: 0.9,
            maxTokens: 1024,
            stream: true
        )

        var accumulated = ""
        var reasoningAccumulated = ""
        let stream = apiClient.streamChatCompletion(request: request)
        var receivedContent = false

        for try await chunk in stream {
            try Task.checkCancellation()
            guard let choice = chunk.choices.first else {
                continue
            }

            if let reasoning = choice.delta?.reasoningContent ?? choice.message?.reasoningContent {
                let trimmed = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    reasoningAccumulated += trimmed
                    updateMessage(id: placeholderId) { message in
                        message.reasoning = reasoningAccumulated
                        message.isLoadingPending = false
                    }
                }
            }

            if let piece = choice.delta?.content ?? choice.message?.content, !piece.isEmpty {
                accumulated += piece
                receivedContent = true
                updateMessage(id: placeholderId) { message in
                    message.text = accumulated
                    message.isStreaming = true
                    message.isLoadingPending = false
                }
            }
        }

        guard receivedContent else {
            throw ZhipuAPIError.invalidResponse
        }

        updateMessage(id: placeholderId) { message in
            message.isStreaming = false
            message.isLoadingPending = false
        }
    }

    private func waitForAsyncResult(
        taskId: String,
        expectingVideo: Bool,
        timeout: TimeInterval = 60,
        pollInterval: TimeInterval = 1.0
    ) async throws -> ZhipuAsyncResultResponse {
        let start = Date()

        while true {
            let result = try await apiClient.fetchAsyncResult(id: taskId)
            try Task.checkCancellation()
            let status = (result.taskStatus ?? "").uppercased()

            let isProcessing = status.isEmpty
                || status == "PROCESSING"
                || status == "PENDING"
                || status == "QUEUED"

            if !isProcessing {
                if expectingVideo {
                    if let videos = result.videoResult, !videos.isEmpty {
                        return result
                    }
                } else {
                    if let choices = result.choices, !choices.isEmpty {
                        return result
                    }
                }
                // 即使没有解析到预期字段，也返回结果，由上层决定如何展示
                return result
            }

            let elapsed = Date().timeIntervalSince(start)
            if elapsed > timeout {
                throw ZhipuAPIError.invalidResponse
            }

            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }
}
