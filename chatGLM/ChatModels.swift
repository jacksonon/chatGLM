import Foundation

enum ChatMode: String, CaseIterable, Identifiable {
    case chat
    case image
    case video

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat:
            return "对话"
        case .image:
            return "文生图"
        case .video:
            return "生成视频"
        }
    }
}

enum ChatSender {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let sender: ChatSender
    var text: String
    var createdAt: Date

    var isStreaming: Bool
    var imageURLs: [URL]
    var videoURL: URL?
    var attachedImageData: Data?
    var attachedFileName: String?

    init(
        id: UUID = UUID(),
        sender: ChatSender,
        text: String,
        createdAt: Date = Date(),
        isStreaming: Bool = false,
        imageURLs: [URL] = [],
        videoURL: URL? = nil,
        attachedImageData: Data? = nil,
        attachedFileName: String? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.createdAt = createdAt
        self.isStreaming = isStreaming
        self.imageURLs = imageURLs
        self.videoURL = videoURL
        self.attachedImageData = attachedImageData
        self.attachedFileName = attachedFileName
    }
}
