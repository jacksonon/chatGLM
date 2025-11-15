# chatGLM

跨平台的 SwiftUI 客户端，封装智谱 GLM 能力，提供类似 ChatGPT 的对话体验，并支持文生图、视频生成和图像理解。目标平台包括 iOS、iPadOS、macOS 与 visionOS。

![chatGLM macOS UI 示例](https://github.com/jacksonon/chatGLM/raw/main/sample1.png)

![chatGLM iOS UI 示例](https://github.com/jacksonon/chatGLM/raw/main/sample2.png)

![chatGLM iPadOS UI 示例](https://github.com/jacksonon/chatGLM/raw/main/sample3.png)

## 架构概览

- `chatGLMApp.swift`: 应用入口，加载统一的聊天界面。
- `ContentView.swift`: 主 UI，基于 SwiftUI 构建 ChatGPT 风格界面，支持多端自适应、动画背景、消息气泡、模式切换和输入区的七色光晕效果。
- `ChatModels.swift`: 聊天领域模型，包含 `ChatMessage`（用户/助手消息）、`ChatMode`（对话 / 文生图 / 视频）。
- `ChatViewModel.swift`: 业务核心：
  - 维护消息列表、输入状态和当前模式。
  - 对话模式：调用对话异步接口，轮询异步结果，并以“打字机”方式流式展示回复。
  - 文生图模式：调用图片生成接口，返回多张图片 URL 并在 UI 中展示。
  - 视频模式：调用视频生成异步接口，并在结果返回后展示视频链接占位卡片。
  - 图片上下文：选取本地图片后，提取基础信息（分辨率等）拼接为提示，作为附加上下文发送给对话模型，实现“图像理解 + 继续对话”。

## LLM 网络层

- 目录：`LLM/`
- `ZhipuModels.swift`: 封装智谱相关请求/响应模型：
  - 对话异步：`ZhipuAsyncChatRequest` / `ZhipuAsyncTaskResponse`
  - 图片生成：`ZhipuImageGenerationRequest` / `ZhipuImageGenerationResponse`
  - 视频生成：`ZhipuVideoGenerationRequest`
  - 异步结果查询：`ZhipuAsyncResultResponse`
- `ZhipuAPIClient.swift`: 基于原生 `URLSession` 的统一客户端：
  - `createAsyncChatCompletion` → `/api/paas/v4/async/chat/completions`
  - `createImageGeneration` → `/api/paas/v4/images/generations`
  - `createVideoGeneration` → `/api/paas/v4/videos/generations`
  - `fetchAsyncResult` → `/api/paas/v4/async-result/{id}`
- 模型枚举 `ZhipuModel` 预置免费模型：
  - `glm-4.5-flash` 对话
  - `glm-4.1v-thinking-flash` 图像理解
  - `cogview-3-flash` 图像生成
  - `cogvideox-flash` 视频生成

## 运行与配置

1. 安装依赖：在 Xcode 中打开 `chatGLM.xcodeproj`（网络层基于系统自带的 `URLSession`，无需额外三方包）。
2. 配置 API Key：在 Xcode Scheme 的 Run 配置里设置环境变量：

   - `ZHIPU_API_KEY=<你的智谱 API Key>`

3. 运行应用：选择目标平台（iOS 模拟器、macOS、visionOS 等）并启动，即可体验多模式对话、文生图和视频生成能力。
