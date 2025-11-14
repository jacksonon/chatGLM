import Foundation
import SwiftData

@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade) var messages: [MessageRecord]

    init(
        id: UUID = UUID(),
        title: String = "新会话",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [MessageRecord] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

@Model
final class MessageRecord {
    @Attribute(.unique) var id: UUID
    var sender: String
    var text: String
    var createdAt: Date
    var imageURLs: [String]
    var videoURL: String?
    var attachedImageData: Data?
    var attachedFileName: String?

    init(
        id: UUID = UUID(),
        sender: String,
        text: String,
        createdAt: Date = Date(),
        imageURLs: [String] = [],
        videoURL: String? = nil,
        attachedImageData: Data? = nil,
        attachedFileName: String? = nil
    ) {
        self.id = id
        self.sender = sender
        self.text = text
        self.createdAt = createdAt
        self.imageURLs = imageURLs
        self.videoURL = videoURL
        self.attachedImageData = attachedImageData
        self.attachedFileName = attachedFileName
    }
}
