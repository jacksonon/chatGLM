# macOS 编辑器集成与应用控制说明

本文档介绍 chatGLM 在 **macOS** 上如何通过辅助功能与自动化权限，集成并“控制” Xcode / VSCode / Warp 等应用，读取当前正在编辑的文件并将其内容纳入对话上下文。

> 当前实现仅支持 **macOS**，不会在 iOS / iPadOS / visionOS 上尝试访问其它应用。

## 整体能力概览

在 macOS 上，chatGLM 支持：

- 在设置界面管理可连接的编辑器（Xcode、VSCode、JetBrains、Warp 等）。
- 在聊天输入框中选择一个正在运行的应用。
- 通过系统的 **辅助功能（Accessibility）** 和 **自动化（Apple Events）**：
  - 读取该应用当前窗口/文档的文件路径；
  - 读取文件内容（最多截断为一定长度的摘要）；
  - 将“文件名 + 文件摘要 + 文件路径”一并发送给智谱 GLM 模型，用于代码分析和改写建议。

目前的版本 **不会自动覆写代码文件**，而是以“读取 + 分析 + 生成修改建议”为主，防止误操作破坏工程。

---

## 关键模块与文件

### 1. 编辑器集成核心：`EditorIntegration.swift`

位置：`chatGLM/MacEditorIntegration/EditorIntegration.swift`（仅在 `os(macOS)` 下编译）

主要职责：

- 定义编辑器应用信息：

  ```swift
  struct EditorAppInfo: Identifiable, Hashable {
      let name: String
      let bundleIdentifier: String
      let icon: NSImage?
      let isInstalled: Bool
      let isRunning: Bool
      let hasAccessibilityPermission: Bool
  }
  ```

- 维护可用应用列表与权限状态：

  ```swift
  final class EditorIntegrationManager: ObservableObject {
      @Published private(set) var apps: [EditorAppInfo] = []
      @Published private(set) var hasAccessibilityPermission: Bool = AXIsProcessTrusted()
      // ...
  }
  ```

- 使用 **辅助功能 API** (`AXUIElement`) 获取当前文档路径：

  1. 通过 `NSRunningApplication.runningApplications(withBundleIdentifier:)` 找到目标进程。
  2. 使用 `AXUIElementCreateApplication(pid)` 创建可访问性对象。
  3. 依次尝试：
     - `kAXFocusedWindowAttribute`
     - `kAXMainWindowAttribute`
     - `kAXFocusedUIElementAttribute` 及父层级中的 `kAXDocumentAttribute`
  4. 解析 `kAXDocumentAttribute` 为文件本地路径。

- 当 AX 无法获取 Xcode 当前文档时，使用 **AppleScript / Apple Events** 兜底：

  ```swift
  tell application id "com.apple.dt.Xcode"
      if (count of documents) is 0 then
          return ""
      end if
      set theDoc to document 1
      set docPath to POSIX path of (path of theDoc)
      return docPath
  end tell
  ```

  该调用依赖自动化权限（见下文“权限与签名”）。如果在个别环境下 Xcode 既未暴露 `AXDocument`，又无法通过 AppleScript 提供文档路径，`EditorIntegration` 会退而求其次：

  - 通过辅助功能遍历 Xcode 的窗口和子元素，找到代码编辑区（`AXTextArea` 等）；
  - 读取当前缓冲区的完整文本，写入沙盒临时目录生成一个临时文件；
  - 将该临时文件的路径返回给上层，用于生成“文件摘要 + 路径”上下文。

  这种方案虽然拿不到真实工程中文件的物理路径，但可以保证至少能基于“当前编辑缓冲区的内容”进行问答与代码分析。

### 2. 设置与应用管理：`SettingsView.swift`

位置：`chatGLM/SettingsView.swift`

macOS 下的设置布局：

- 左侧「使用应用」分区：
  - 提供“管理应用”按钮，弹出 `AppManagementView`。
- 右侧「智谱设置」分区：
  - 配置智谱 API Key。

`AppManagementView` 中使用 `EditorIntegrationManager`：

- 展示当前已安装的编辑器列表（Xcode / VSCode / JetBrains / Warp / 终端等）；
- 显示每个应用的状态（已安装 / 缺少辅助功能权限 / 应用未运行 / 已可通过可访问性使用）；
- 提供：
  - 「打开辅助功能设置」按钮：跳转到 `隐私与安全性 > 辅助功能`；
  - 「再次请求权限」按钮：调用 `AXIsProcessTrustedWithOptions(prompt: true)` 主动发起权限请求。

### 3. macOS 设置窗口：`SettingsWindowController.swift`

位置：`chatGLM/MacEditorIntegration/SettingsWindowController.swift`

用途：

- 在 macOS 上使用独立的 `NSWindow` 承载 `SettingsView`，而不是 SwiftUI `.sheet`。
- 解决设置窗口关闭后无法再次打开的问题：
  - `SettingsWindowController` 持有 `NSWindow` 引用；
  - 在 `windowWillClose` 中将该引用清空；
  - 下次点击侧边栏的“…”按钮，会重新创建一个新的设置窗口。

### 4. 聊天输入中的“应用选择”：`ContentView.swift`（`RainbowGlowInputBar`）

位置：`chatGLM/ContentView.swift` 中 `RainbowGlowInputBar` 结构体（仅 macOS 有应用选择按钮）。

关键点：

- 在输入框辅助区域新增了一个 macOS 专用按钮：

  ```swift
  #if os(macOS)
  Button {
      showAppPicker = true
  } label: {
      Image(systemName: "macwindow")
          .foregroundStyle(.secondary)
  }
  #endif
  ```

- 点击后弹出 `EditorAppPickerView`（定义在 `EditorIntegration.swift`）：
  - 支持搜索应用。
  - 将已安装、已运行且已授予辅助功能权限的应用列在“使用应用”分区。

- 在 `onSelect` 回调中：

  ```swift
  EditorAppPickerView(manager: editorManager) { app in
      if let context = editorManager.currentFileContext(for: app) {
          Task {
              await loadFileContext(from: context.fileURL)
          }
      } else {
          // 在 UI 上给出无法获取文件的提示
      }
  }
  ```

- `loadFileContext(from:)` 会：
  - 读取文件内容；
  - 做长度截断，生成摘要；
  - 将文件名、摘要、路径写入 `ChatViewModel`：
    - `selectedFileName`
    - `selectedFileSummary`
    - `selectedFileURL`

- 在输入框上方会显示“当前文件卡片”，让用户确认上下文是否正确。

### 5. 将文件上下文传给 LLM：`ChatViewModel.swift`

位置：`chatGLM/ChatViewModel.swift`

在对话模式下，`handleChat(userMessage:)` 会将文件信息拼入发送给模型的内容中：

```swift
let fileContext = selectedFileSummary
// ...
if let fileContext {
    let fileNamePart = selectedFileName ?? "选中文件"
    var extra = "\n\n附加文件（\(fileNamePart)）内容摘要：\(fileContext)"
    if let url = selectedFileURL {
        extra.append("\n文件路径：\(url.path)")
    }
    content.append(extra)
}
```

LLM 因此可以：

- 结合当前对话历史；
- 加上“当前文件的摘要 + 路径”；
- 做静态代码分析、找 bug、给出改写建议或完整的新版本。

当前实现 **不自动修改文件**，由用户将建议手动粘贴回编辑器。后续如需自动写回，可以在此基础上扩展。

---

## 权限与签名配置

为了访问其它应用的 UI 结构和文档路径，macOS 端需要两类权限：**辅助功能** 和 **自动化（Apple Events）**。

### 1. 辅助功能（Accessibility）

主要 API：

- `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions`
- `AXUIElementCreateApplication`
- `AXUIElementCopyAttributeValue`

配置与交互流程：

1. 应用启动或打开“管理应用”时调用：

   ```swift
   let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
   let options: NSDictionary = [key: true as CFBoolean]
   let trusted = AXIsProcessTrustedWithOptions(options)
   ```

2. 若当前未被授权，系统会弹出“允许 ChatGLM 控制这台电脑”的原生对话框。
3. 用户在「系统设置 > 隐私与安全性 > 辅助功能」中勾选 ChatGLM 后即可生效。

### 2. 自动化（Apple Events）

用于向 Xcode 发送 AppleScript：

- 查询 `document 1` 的路径；
- 在某些 AX 无法覆盖的场景下作为兜底方案。

配置步骤：

1. 在 `chatGLM/chatGLM.entitlements` 中开启：

   ```xml
   <key>com.apple.security.app-sandbox</key>
   <true/>
   <key>com.apple.security.automation.apple-events</key>
   <true/>
   ```

2. 在 `project.pbxproj` 中，针对 macOS SDK 绑定该 entitlements：

   ```pbxproj
   "CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = chatGLM/chatGLM.entitlements;
   ```

3. 在 Info.plist（通过 `INFOPLIST_KEY_NSAppleEventsUsageDescription`）声明用途：

   ```pbxproj
   INFOPLIST_KEY_NSAppleEventsUsageDescription = "允许 ChatGLM 控制 Xcode、VSCode 等应用以读取当前编辑的文件，从而协助用户完成代码修改和开发工作。";
   ```

首次从 ChatGLM 控制 Xcode 时，系统会弹出自动化授权对话框，用户同意后方可继续使用。

---

## 使用说明（macOS）

1. **运行 Mac 版本**
   - 在 Xcode 顶部 Scheme 中选择 “My Mac” 目标；
   - Build & Run。

2. **授予辅助功能与自动化权限**
   - 打开 chatGLM 设置 → “管理应用”；
   - 根据提示在「隐私与安全性 > 辅助功能」中勾选 ChatGLM；
   - 首次从 chatGLM 控制 Xcode 时，系统会弹出自动化授权对话框，请选择“允许”。

3. **选择目标编辑器**
   - 确保 Xcode / VSCode 等应用已运行，并打开了一个代码文件；
   - 在聊天输入框区域点击“应用选择”按钮（macOS 专有的图标按钮）；
   - 在弹出的列表中选择 Xcode 或其它编辑器；
   - 若成功，输入框上方会出现当前文件卡片（文件名 + 内容摘要）。

4. **进行对话与代码分析**
   - 在输入框中描述需要的操作，如“帮我找出当前文件中可能的内存泄漏”；
   - 发送后，模型会结合文件摘要和路径给出分析与修改建议；
   - 如需修改代码，可将建议手动粘贴回 Xcode 中。

---

## 后续扩展方向

- **自动写回文件**：在已有 `selectedFileURL` 基础上，增加一个可选的“应用修改”流程：
  - 约定模型输出补丁格式；
  - 在用户确认后将修改写回 `.swift` 文件；
  - 与 Xcode 的 Source Control 集成（如自动 `git diff` 预览）。
- **更丰富的编辑器支持**：
  - 针对 JetBrains IDE、VSCode 增加更精准的 AppleScript / 可访问性适配；
  - 或通过各自的插件 API 建立更稳定的连接。

当前版本已经具备“读取并理解当前编辑文件”的基础能力，在保证安全可控的前提下，未来可以进一步演进为更完整的“AI 驱动代码助手”。

---

## 通过“隐私-辅助功能”操作 App 的整体方案说明

本节抽象总结一套可复用的方案，用于让类似 ChatGPT / ChatGLM 的本地桌面应用，通过 **隐私-辅助功能** 与 **自动化（Apple Events）** 对其它 App（如 Xcode、VSCode、终端等）进行“可控的交互”，以便实现：

- 获取目标应用当前窗口 / 文本内容；
- 将内容送入大模型进行问答、代码分析；
- 在安全可控范围内回写或辅助用户修改。

### 1. 能力边界与 Apple 官方约束

根据 Apple 官方文档，这类工具需要遵守以下硬性边界：

- **辅助功能（Accessibility）能做的事**：
  - 读取其它 App 的可访问性树：窗口、控件、文本内容等（`AXUIElement`、`AXValue`、`AXRole` 等）；
  - 以辅助技术的身份模拟基本交互（点击按钮、输入文字）。
- **辅助功能不能做的事**：
  - 不提供任意进程调试能力（`task_for_pid` 需要调试器专用 entitlement）；
  - 不构成“文件系统越权通行证”，不能绕过 App Sandbox / TCC 随意读写对方文件；
  - 能否拿到文档路径（`AXDocument`）由目标 App 自愿暴露。
- **Apple Events / 自动化能做的事**：
  - 向 Xcode 等支持脚本的应用发送 AppleScript / AppleEvent，执行“获取当前文档路径”等脚本命令；
  - 受系统“隐私-自动化”保护，首次调用需弹框，用户明确允许。

因此，一个合规、安全的“AI 控制其它 App”方案，必须同时满足：

- 用户显式授予：**辅助功能** + **自动化（若用 AppleScript）**；
- 不尝试使用调试器类 restricted entitlements（如 `com.apple.security.cs.debugger`）；
- 文件访问能力仅在：
  - 用户选中文件（NSOpenPanel / 文件选择）；
  - 或目标 App 自己通过 AX / AppleScript 提供路径的前提下进行。

### 2. 整体架构分层

可以将实现拆成三层：

1. **App 管理与权限层**
   - 维护一个支持的应用列表：名称 + bundle id（Xcode、VSCode、JetBrains、终端等）；
   - 每次刷新时检查：
     - 是否安装（`NSWorkspace.urlForApplication`）；
     - 是否正在运行（`NSRunningApplication.runningApplications`）；
     - 本应用是否已被授予辅助功能权限（`AXIsProcessTrusted()`）；
   - 提供 UI 引导用户：
     - 打开「系统设置 > 隐私与安全性 > 辅助功能」；
     - 如有 AppleScript，首次发送时触发自动化授权对话框。

2. **上下文发现层（从目标 App 获取“当前上下文”）**
   - 针对每个支持的 App，定义一套“如何找到当前上下文”的策略：
     - 通用流程：
       - 通过 `AXUIElementCreateApplication(pid)` 拿到应用级 AX 根；
       - 从 `kAXFocusedWindowAttribute` / `kAXMainWindowAttribute` / `kAXFocusedUIElementAttribute` 递归向上寻找带 `kAXDocumentAttribute` 的元素；
       - 如果找到 `AXDocument`，转成本地文件 URL。
     - 针对 Xcode 等特殊应用的扩展：
       - 使用 AppleScript 询问当前文档路径（如 `document 1` 的 `path`）；
       - 如果 AX 与 AppleScript 都拿不到路径，则通过辅助功能：
         - 遍历窗口层级，找到代码编辑区域（`AXTextArea` / 文本控件）；
         - 读取完整文本，写入本应用沙盒下的临时文件；
         - 将该临时文件作为“当前缓冲区”的载体提供给大模型。

3. **大模型交互层**
   - 将“用户问题 + 当前 App 上下文（文件名 / 路径 / 内容片段）”打包为 prompt：
     - 支持附加说明：这是来自 Xcode 当前编辑文件 / 这是缓冲区临时文件路径等；
   - 接收模型输出：
     - 解析结果为“分析 + 修改建议 + 可能的补丁片段”；
     - 当前版本仅展示，不自动写回；
     - 如将来支持自动应用修改，需在此层生成结构化补丁，并由用户确认后再调用文件写入 / 模拟编辑操作。

### 3. 用户授权与权限处理流程

1. **第一次使用时**：
   - App 启动或用户打开“管理应用 / 选择应用”时调用：
     - `AXIsProcessTrustedWithOptions(prompt: true)`，请求辅助功能授权；
   - 用户在系统设置中勾选本应用，授权完成后再刷新状态。

2. **首次控制支持 AppleScript 的 App（如 Xcode）时**：
   - 执行 AppleScript（例如查询 `document 1` 的路径）；
   - 系统弹出“是否允许 XXX 控制 Xcode？”对话框；
   - 用户允许后，后续 AppleScript 调用生效。

3. **文件访问**：
   - 若通过 `AXDocument` / AppleScript 得到真实路径，再由当前 App 根据自身沙盒 / 用户选取授权访问该文件；
   - 若只能拿到缓冲区文本，则写入应用沙盒内的临时文件，避免直接依赖目标 App 的工程结构。

### 4. ChatGPT/ChatGLM 视角下的典型使用路径

以“AI 助理帮助修改 Xcode 当前文件”为例，交互链路如下：

1. 用户在 Xcode 中打开一个 `.swift` 文件，并将插入点放在需要分析的位置；
2. 打开 ChatGLM / ChatGPT 桌面 App，点击“选择应用”，选中 Xcode：
   - App 通过辅助功能 + AppleScript 获取当前文件路径或缓冲区文本；
   - 读取内容生成摘要（必要时截断），并在 UI 上显示“当前文件卡片”；
3. 用户在聊天框中描述需求，例如“帮我重构当前函数，减少重复逻辑”；
4. App 将：
   - 用户输入；
   - 当前文件摘要 + 路径（或临时文件路径）；
   - 必要的上下文（项目类型、语言等）
   一并发送给大模型；
5. 模型返回分析与修改建议，用户视情况手动复制到 Xcode 中；
6. 将来如支持自动应用修改：
   - 模型返回结构化补丁；
   - 本地 App 在用户确认后，通过文件写入或模拟编辑操作应用修改。

### 5. 方案的优点与局限

- **优点**：
  - 严格遵守 Apple 的隐私与安全模型（辅助功能 + 自动化 + 沙盒文件访问），不依赖私有 API 或调试器 entitlement；
  - 对绝大多数 Editor / Terminal 等无需特殊插件即可工作；
  - 在拿不到真实文档路径时仍能退化到“基于当前缓冲区内容”的问答与分析。
- **局限**：
  - 不能绕过 App Sandbox / TCC 访问任意文件；
  - `AXDocument` 暴露与否由目标 App 决定，路径不可完全依赖；
  - 对复杂 UI（多编辑器 pane / 分屏）时，可能需要针对各家编辑器做更细致的 AX 适配。

这套方案可以视为“面向本地大模型桌面 App 的官方友好路径”：以“辅助技术 + 自动化”的角色，与其它 App 协作完成代码理解和编辑，而不是试图取得类似调试器那样的完全控制权。
