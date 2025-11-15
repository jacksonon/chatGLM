# chatGLM

跨平台的 SwiftUI 客户端，封装智谱 GLM 能力，提供类似 ChatGPT 的对话体验，并支持对话、文生图、视频生成和图像理解。目标平台包括 iOS、iPadOS、macOS 与 visionOS。

> 英文版说明见 `README.md`。

![chatGLM macOS UI 示例](https://github.com/jacksonon/chatGLM/raw/main/sample1.png)

![chatGLM iOS UI 示例](https://github.com/jacksonon/chatGLM/raw/main/sample2.png)

![chatGLM iPadOS UI 示例](https://github.com/jacksonon/chatGLM/raw/main/sample3.png)

在 macOS 上，chatGLM 可以通过 **辅助功能（Accessibility）** 与 **自动化（Apple Events）** 读取 Xcode / VSCode 等编辑器当前打开的文件（或至少是当前编辑缓冲区的内容），并将其作为上下文提供给大模型。  
详细说明见：`MacEditorIntegration.md`。

---

## 功能特性

- **多平台 SwiftUI 应用**
  - 单一代码库同时支持 iOS、iPadOS、macOS、visionOS。
  - 针对 iPhone / iPad / Mac 的自适应布局，带动画背景与聊天气泡样式。

- **对话 / 图片 / 视频一体化**
  - 对话模式：流式回复，体验接近 ChatGPT。
  - 文生图模式：根据文本生成图片。
  - 文生视频模式：根据文本生成视频。

- **图像理解**
  - 支持附加本地图片；
  - 应用会提取图像基础信息（尺寸、格式等），作为额外上下文注入到对话提示中，让模型具备“看图说话”的能力。

- **macOS 编辑器集成**
  - 自动发现常见编辑器（Xcode、VSCode、JetBrains 系列、终端工具等）。
  - 在用户授予“辅助功能 + 自动化”权限后，可以从目标应用中读取“当前文件”（或当前编辑缓冲区），并在对话中附加：
    - 文件名；
    - 截断后的内容摘要；
    - 文件路径或临时文件路径。
  - 当前版本仅做 **只读分析**，不会自动修改工程文件，避免误操作。
  - 相关实现与权限配置详见 `MacEditorIntegration.md` 以及 `chatGLM/MacEditorIntegration/` 目录。

---

## 架构概览

整体结构：

- `chatGLMApp.swift`
  - 应用入口。
  - 负责加载统一的聊天界面。

- `ContentView.swift`
  - 主聊天界面（SwiftUI）。
  - 提供 ChatGPT 风格的聊天体验：背景渐变、消息列表、模式切换、带“彩虹光晕”的输入栏等。
  - 在 macOS 下集成了“应用选择”按钮，可选择正在运行的编辑器应用并附加其当前文件作为上下文。

- `ChatModels.swift`
  - 聊天领域模型：
    - `ChatMessage` – 用户 / 助手消息，附带可选图片或文件信息。
    - `ChatMode` – `.chat`（对话）、`.image`（文生图）、`.video`（文生视频）。

- `ChatViewModel.swift`
  - 业务核心：
    - 管理消息列表、输入状态与当前模式；
    - **对话模式**：
      - 调用异步对话接口；
      - 轮询异步结果；
      - 将最终回复以“打字机”方式逐字渲染；
    - **文生图模式**：
      - 调用图片生成接口；
      - 显示返回的图片 URL；
    - **文生视频模式**：
      - 调用视频生成异步接口；
      - 使用卡片展示生成的视频链接；
    - **文件 / 图片上下文**：
      - 对图片：拼接简要描述加入 prompt；
      - 对文件（来自文件选择或编辑器集成）：截断内容生成摘要，并附带路径，一并发送给模型用于代码分析与改写建议。

- 其他组件
  - `PlatformImage.swift`、`MultilineInputView.swift` 等：封装平台差异与可复用 UI 组件。

### macOS 专用模块

- 目录：`chatGLM/MacEditorIntegration/`
  - `EditorIntegration.swift`
    - 使用 `NSWorkspace` 与 `NSRunningApplication` 发现已安装 / 正在运行的编辑器。
    - 使用辅助功能（`AXUIElement`）尝试通过以下属性获取当前文档路径：
      - `kAXFocusedWindowAttribute`
      - `kAXMainWindowAttribute`
      - `kAXFocusedUIElementAttribute`，并向父层级回溯查找 `kAXDocumentAttribute`。
    - 针对 Xcode：
      - 首先尝试 AppleScript 获取当前文档的 POSIX 路径；
      - 如果辅助功能与 AppleScript 都拿不到路径，则退而求其次：
        - 遍历 Xcode 窗口的可访问性树，寻找代码编辑区域（如 `AXTextArea`）；
        - 读取当前编辑缓冲区的完整文本；
        - 将文本写入应用沙盒内的临时文件；
        - 将该临时文件的 URL 作为“当前文件”返回给上层。
    - 对外暴露 `EditorIntegrationManager` 与 `EditorAppPickerView`，供设置页和输入栏调用。
  - `SettingsWindowController.swift`
    - 在 macOS 上使用独立 `NSWindow` 承载 `SettingsView`，与主聊天窗口分离。

更多权限配置与行为说明见 `MacEditorIntegration.md`。

---

## LLM 网络层

- 目录：`chatGLM/LLM/`

- `ZhipuModels.swift`
  - 封装智谱接口的请求 / 响应模型：
    - 异步对话：`ZhipuAsyncChatRequest`、`ZhipuAsyncTaskResponse`
    - 图片生成：`ZhipuImageGenerationRequest`、`ZhipuImageGenerationResponse`
    - 视频生成：`ZhipuVideoGenerationRequest`
    - 异步结果查询：`ZhipuAsyncResultResponse`
  - `ZhipuModel` 枚举预置常用模型：
    - `glm-4.5-flash` – 对话模型
    - `glm-4.1v-thinking-flash` – 图像理解 / 多模态模型
    - `cogview-3-flash` – 文生图模型
    - `cogvideox-flash` – 文生视频模型

- `ZhipuAPIClient.swift`
  - 基于系统 `URLSession` 的轻量封装，提供：
    - `createAsyncChatCompletion` → `/api/paas/v4/async/chat/completions`
    - `createImageGeneration` → `/api/paas/v4/images/generations`
    - `createVideoGeneration` → `/api/paas/v4/videos/generations`
    - `fetchAsyncResult` → `/api/paas/v4/async-result/{id}`

网络层不依赖第三方网络库，方便集成与调试。

---

## 运行与配置

1. **打开工程**
   - 使用 Xcode 打开 `chatGLM.xcodeproj`。

2. **配置智谱 API Key**
   - 在 Xcode 的 Run Scheme 中添加环境变量：

     - `ZHIPU_API_KEY=<你的智谱 API Key>`

3. **选择目标平台并运行**
   - 可选择：
     - iOS 模拟器 / 真机；
     - “My Mac”（macOS App）；
     - visionOS 模拟器（如已安装）。
   - 编译并运行即可体验多模式对话、文生图与视频生成功能。

4. **授予 macOS 权限（可选但推荐）**
   - 若希望使用编辑器集成功能：
     - 在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 chatGLM；
     - 首次通过 AppleScript 控制 Xcode 时，系统会弹出“自动化”权限提示，请选择允许。
   - 完成上述配置后，即可在聊天输入区点击“应用选择”按钮，选择 Xcode 或 VSCode 等正在运行的应用，将“当前文件（或当前编辑缓冲区）”作为上下文交给大模型进行分析与建议生成。 

