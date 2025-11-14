import Foundation
import Combine
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var mode: ChatMode = .chat
    @Published var isSending: Bool = false
    @Published var selectedImageData: Data?
    @Published var selectedFileSummary: String?
    @Published var selectedFileName: String?

    private let apiClient: ZhipuAPIClient

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

        Task {
            await send(for: userMessage)
        }
    }

    private func send(for userMessage: ChatMessage) async {
        isSending = true
        defer {
            isSending = false
            selectedImageData = nil
            selectedFileSummary = nil
            selectedFileName = nil
        }

        switch mode {
        case .chat:
            await handleChat(userMessage: userMessage)
        case .image:
            await handleImageGeneration(userMessage: userMessage)
        case .video:
            await handleVideoGeneration(userMessage: userMessage)
        }
    }

    private func handleChat(userMessage: ChatMessage) async {
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
            let extra = "\n\n附加文件（\(fileNamePart)）内容摘要：\(fileContext)"
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
            isStreaming: true
        )
        messages.append(placeholder)

        do {
            let asyncTask = try await apiClient.createAsyncChatCompletion(request: request)
            let result = try await apiClient.fetchAsyncResult(id: asyncTask.id)
            let fullText = result.choices?.first?.message?.content ?? ""
            try await animateStreamingReply(fullText: fullText, for: placeholder.id)
        } catch {
            let messageText = friendlyErrorMessage(error)
            updateMessage(id: placeholder.id) { message in
                message.text = messageText
                message.isStreaming = false
            }
        }
    }

    private func handleImageGeneration(userMessage: ChatMessage) async {
        let request = ZhipuImageGenerationRequest(
            model: .cogview3Flash,
            prompt: userMessage.text,
            size: "1024x1024"
        )

        let placeholder = ChatMessage(
            sender: .assistant,
            text: "正在生成图片...",
            isStreaming: true
        )
        messages.append(placeholder)

        do {
            let response = try await apiClient.createImageGeneration(request: request)
            let urls = response.data.compactMap { URL(string: $0.url) }
            updateMessage(id: placeholder.id) { message in
                message.text = "图片已生成"
                message.imageURLs = urls
                message.isStreaming = false
            }
        } catch {
            let messageText = friendlyErrorMessage(error, prefix: "图片生成失败")
            updateMessage(id: placeholder.id) { message in
                message.text = messageText
                message.isStreaming = false
            }
        }
    }

    private func handleVideoGeneration(userMessage: ChatMessage) async {
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
            text: "正在生成视频...",
            isStreaming: true
        )
        messages.append(placeholder)

        do {
            let asyncTask = try await apiClient.createVideoGeneration(request: request)
            let result = try await apiClient.fetchAsyncResult(id: asyncTask.id)
            let videoURL = result.videoResult?.first.flatMap { URL(string: $0.url) }

            updateMessage(id: placeholder.id) { message in
                message.text = videoURL == nil ? "视频生成完成" : ""
                message.videoURL = videoURL
                message.isStreaming = false
            }
        } catch {
            let messageText = friendlyErrorMessage(error, prefix: "视频生成失败")
            updateMessage(id: placeholder.id) { message in
                message.text = messageText
                message.isStreaming = false
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
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        updateMessage(id: id) { message in
            message.isStreaming = false
        }
    }

    private func friendlyErrorMessage(_ error: Error, prefix: String = "请求失败") -> String {
        if let apiError = error as? ZhipuAPIError {
            return "\(prefix)：\(apiError.localizedDescription)"
        } else {
            return "\(prefix)：\(error.localizedDescription)"
        }
    }
}
