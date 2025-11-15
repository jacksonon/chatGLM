# chatGLM

**中文说明 / Chinese README:** [README-zh.md](README-zh.md)

Cross‑platform SwiftUI client for Zhipu GLM models.  
Provides a ChatGPT‑style experience with chat, image generation, video generation, and image understanding, targeting iOS, iPadOS, macOS, and visionOS.

![chatGLM macOS UI](https://github.com/jacksonon/chatGLM/raw/main/sample1.png)

![chatGLM iOS UI](https://github.com/jacksonon/chatGLM/raw/main/sample2.png)

![chatGLM iPadOS UI](https://github.com/jacksonon/chatGLM/raw/main/sample3.png)

On macOS, chatGLM can read the file currently being edited in Xcode / VSCode and other editors via **Accessibility** and **Automation (Apple Events)**.  
Details: `MacEditorIntegration.md`.

---

## Features

- **Multi‑platform SwiftUI app**
  - Single codebase targeting iOS, iPadOS, macOS, and visionOS.
  - Adaptive layouts for iPhone, iPad, and Mac, with animated background and chat bubbles.

- **Chat, images, and video**
  - Chat mode with streaming responses.
  - Image generation mode (text‑to‑image).
  - Video generation mode (text‑to‑video).

- **Image understanding**
  - Attach a local image.
  - The app extracts basic info (size, format, etc.) and injects it as extra context for the chat model.

- **macOS editor integration**
  - Discover common editors (Xcode, VSCode, JetBrains IDEs, terminal tools, etc.).
  - With user‑granted Accessibility + Automation permissions, read the current file (or at least the current editor buffer) from the target app and attach it as context for the model.
  - Current version is **read‑only**: it doesn’t auto‑modify your code files; it focuses on analysis and suggestions.
  - See `MacEditorIntegration.md` and `chatGLM/MacEditorIntegration/`.

---

## Architecture Overview

High‑level structure:

- `chatGLMApp.swift`
  - App entry point.
  - Loads the shared chat UI.

- `ContentView.swift`
  - Main SwiftUI view.
  - Provides the ChatGPT‑style chat interface, background gradient, message list, mode picker, and the “rainbow glow” input bar.
  - On macOS, integrates the editor picker button that lets you choose a running editor app and attach its current file as context.

- `ChatModels.swift`
  - Domain models:
    - `ChatMessage` – user/assistant messages, optional image/file attachment metadata.
    - `ChatMode` – `.chat`, `.image`, `.video`.

- `ChatViewModel.swift`
  - Core business logic:
    - Maintains message history, input state, and current mode.
    - **Chat mode**:
      - Calls the async chat completion API.
      - Polls the async result.
      - Streams the final answer into the UI with a “typewriter” effect.
    - **Image mode**:
      - Calls the image generation API.
      - Displays returned image URLs.
    - **Video mode**:
      - Calls the video generation async API.
      - Shows a card with the resulting video URL.
    - **File / image context**:
      - For attached images: injects a short description into the prompt.
      - For attached files (from file picker or editor integration): adds a truncated snippet plus path to the prompt so the model can reason about the code.

- `PlatformImage.swift`, `MultilineInputView.swift`, etc.
  - Small platform‑adaptation helpers and UI components.

### macOS‑specific integration

- Folder: `chatGLM/MacEditorIntegration/`
  - `EditorIntegration.swift`
    - Discovers known editors using `NSWorkspace` and `NSRunningApplication`.
    - Uses Accessibility (`AXUIElement`) to try to obtain the current document path via:
      - `kAXFocusedWindowAttribute`
      - `kAXMainWindowAttribute`
      - `kAXFocusedUIElementAttribute` + climbing parents to find `kAXDocumentAttribute`.
    - For Xcode:
      - First attempts AppleScript to get the current document’s POSIX path.
      - If both Accessibility and AppleScript fail to yield a path, it falls back to:
        - Traversing the Accessibility window tree to find the code editor text area.
        - Reading the full editor buffer text.
        - Writing it to a temporary file inside chatGLM’s sandbox.
        - Returning that temp file URL as “current file” context.
    - Exposes this via `EditorIntegrationManager` and `EditorAppPickerView`.
  - `SettingsWindowController.swift`
    - Hosts `SettingsView` inside an `NSWindow` on macOS, separate from the main chat window.

For a detailed explanation of permissions and behavior, see `MacEditorIntegration.md`.

---

## LLM Networking Layer

- Folder: `chatGLM/LLM/`

- `ZhipuModels.swift`
  - Request/response types for Zhipu APIs:
    - Async chat: `ZhipuAsyncChatRequest`, `ZhipuAsyncTaskResponse`.
    - Image generation: `ZhipuImageGenerationRequest`, `ZhipuImageGenerationResponse`.
    - Video generation: `ZhipuVideoGenerationRequest`.
    - Async result polling: `ZhipuAsyncResultResponse`.
  - `ZhipuModel` enum with common models:
    - `glm-4.5-flash` – chat.
    - `glm-4.1v-thinking-flash` – vision / image understanding.
    - `cogview-3-flash` – image generation.
    - `cogvideox-flash` – video generation.

- `ZhipuAPIClient.swift`
  - A thin wrapper around `URLSession` with convenient methods:
    - `createAsyncChatCompletion` → `/api/paas/v4/async/chat/completions`
    - `createImageGeneration` → `/api/paas/v4/images/generations`
    - `createVideoGeneration` → `/api/paas/v4/videos/generations`
    - `fetchAsyncResult` → `/api/paas/v4/async-result/{id}`

No third‑party networking library is required.

---

## Configuration & Running

1. **Open the project**
   - Open `chatGLM.xcodeproj` in Xcode.

2. **Configure your Zhipu API key**
   - In your Run scheme, add an environment variable:

     - `ZHIPU_API_KEY=<your Zhipu API key>`

3. **Run on a target platform**
   - Select the desired destination:
     - iOS Simulator / physical device.
     - `My Mac` (macOS app).
     - visionOS simulator (if installed).
   - Build and run.

4. **Grant macOS permissions (optional, but recommended)**
   - For editor integration on macOS:
     - In “Privacy & Security → Accessibility”, allow chatGLM to control your Mac.
     - On first AppleScript use (e.g., Xcode integration), approve Automation permission when macOS prompts.
   - After that, you can pick a running editor in the chat input bar and chatGLM will attach the current file (or editor buffer) as context for the model. 
