//
//  ZhipuModels.swift
//  chatGLM
//
//  Created by os on 2025/11/14.
//

import Foundation

enum ZhipuModel: String {
    case glm45Flash = "glm-4.5-flash"
    case glm41VThinkingFlash = "glm-4.1v-thinking-flash"
    case cogview3Flash = "cogview-3-flash"
    case cogVideoXFlash = "cogvideox-flash"
}

struct ZhipuChatMessage: Encodable {
    let role: String
    let content: String
}

struct ZhipuAsyncChatRequest: Encodable {
    let model: String
    let messages: [ZhipuChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let stream: Bool?

    init(model: ZhipuModel, messages: [ZhipuChatMessage], temperature: Double? = nil, maxTokens: Int? = nil, stream: Bool? = nil) {
        self.model = model.rawValue
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

struct ZhipuVideoGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let quality: String?
    let withAudio: Bool?
    let size: String?
    let fps: Int?

    init(model: ZhipuModel, prompt: String, quality: String? = nil, withAudio: Bool? = nil, size: String? = nil, fps: Int? = nil) {
        self.model = model.rawValue
        self.prompt = prompt
        self.quality = quality
        self.withAudio = withAudio
        self.size = size
        self.fps = fps
    }

    enum CodingKeys: String, CodingKey {
        case model
        case prompt
        case quality
        case withAudio = "with_audio"
        case size
        case fps
    }
}

struct ZhipuImageGenerationRequest: Encodable {
    let model: String
    let prompt: String
    let size: String?

    init(model: ZhipuModel, prompt: String, size: String? = nil) {
        self.model = model.rawValue
        self.prompt = prompt
        self.size = size
    }
}

struct ZhipuAsyncTaskResponse: Decodable {
    let model: String?
    let id: String
    let requestId: String?
    let taskStatus: String

    enum CodingKeys: String, CodingKey {
        case model
        case id
        case requestId = "request_id"
        case taskStatus = "task_status"
    }
}

struct ZhipuImageGenerationResponse: Decodable {
    struct ImageData: Decodable {
        let url: String
    }

    struct ContentFilter: Decodable {
        let role: String
        let level: Int
    }

    let created: Int
    let data: [ImageData]
    let contentFilter: [ContentFilter]?

    enum CodingKeys: String, CodingKey {
        case created
        case data
        case contentFilter = "content_filter"
    }
}

struct ZhipuAsyncResultResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case role
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let index: Int
        let message: Message?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }

    struct VideoResult: Decodable {
        let url: String
        let coverImageURL: String?

        enum CodingKeys: String, CodingKey {
            case url
            case coverImageURL = "cover_image_url"
        }
    }

    struct ContentFilter: Decodable {
        let role: String
        let level: Int
    }

    let id: String
    let requestId: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
    let videoResult: [VideoResult]?
    let contentFilter: [ContentFilter]?
    let taskStatus: String?

    enum CodingKeys: String, CodingKey {
        case id
        case requestId = "request_id"
        case created
        case model
        case choices
        case videoResult = "video_result"
        case contentFilter = "content_filter"
        case taskStatus = "task_status"
    }
}

struct ZhipuStreamResponse: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let reasoningContent: String?
            let role: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case role
            }
        }

        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let delta: Delta?
        let message: Message?
        let finishReason: String?
        let index: Int?

        enum CodingKeys: String, CodingKey {
            case delta
            case message
            case finishReason = "finish_reason"
            case index
        }
    }

    let choices: [Choice]
}
