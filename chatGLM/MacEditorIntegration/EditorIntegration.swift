import Foundation

#if os(macOS)
import AppKit
import ApplicationServices
import SwiftUI
import Combine

/// 表示一个可供 ChatGLM 连接的桌面应用（例如 Xcode / VSCode）。
struct EditorAppInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let icon: NSImage?

    let isInstalled: Bool
    let isRunning: Bool
    let hasAccessibilityPermission: Bool

    var isConnectable: Bool {
        isInstalled && hasAccessibilityPermission
    }
}

/// 表示当前文件上下文（用于从目标应用中读取文件内容）。
struct EditorFileContext {
    let app: EditorAppInfo
    let fileURL: URL
}

/// 负责扫描可用编辑器、检查辅助功能权限，并尝试读取目标应用当前文档。
final class EditorIntegrationManager: ObservableObject {
    @Published private(set) var apps: [EditorAppInfo] = []
    @Published private(set) var hasAccessibilityPermission: Bool = AXIsProcessTrusted()

    /// 支持的常见编辑器 / 代码相关应用。可根据需要扩展。
    private let knownApps: [(name: String, bundleId: String)] = [
        ("Xcode", "com.apple.dt.Xcode"),
        ("Code", "com.microsoft.VSCode"),
        ("Android Studio", "com.google.android.studio"),
        ("CLion", "com.jetbrains.CLion"),
        ("JetBrains Rider", "com.jetbrains.rider"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("终端", "com.apple.Terminal"),
        ("备忘录", "com.apple.Notes"),
        ("文本编辑", "com.apple.TextEdit"),
        ("脚本编辑器", "com.apple.ScriptEditor2")
    ]

    init() {
        print("[EditorIntegration] init, trusted=\(AXIsProcessTrusted())")
        refresh()
    }

    /// 重新扫描可用应用及其状态。
    func refresh() {
        hasAccessibilityPermission = AXIsProcessTrusted()
        print("[EditorIntegration] refresh, trusted=\(hasAccessibilityPermission)")

        let workspace = NSWorkspace.shared
        var result: [EditorAppInfo] = []

        for item in knownApps {
            let bundleId = item.bundleId
            let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId)
            let isInstalled = (appURL != nil)

            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            let isRunning = !runningApps.isEmpty

            let icon: NSImage?
            if let appURL {
                icon = workspace.icon(forFile: appURL.path)
            } else {
                icon = nil
            }

            let info = EditorAppInfo(
                name: item.name,
                bundleIdentifier: bundleId,
                icon: icon,
                isInstalled: isInstalled,
                isRunning: isRunning,
                hasAccessibilityPermission: hasAccessibilityPermission
            )
            result.append(info)
        }

        // 按是否安装和是否正在运行排序，已安装且运行中的放前面。
        apps = result.sorted { lhs, rhs in
            if lhs.isInstalled != rhs.isInstalled {
                return lhs.isInstalled && !rhs.isInstalled
            }
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// 请求辅助功能权限，并弹出系统提示。
    func requestAccessibilityPermission() {
        print("[EditorIntegration] requestAccessibilityPermission() invoked")
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
        let options: NSDictionary = [key: true as CFBoolean]
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("[EditorIntegration] AXIsProcessTrustedWithOptions returned trusted=\(trusted)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            print("[EditorIntegration] refresh after permission request")
            self?.refresh()
        }
    }

    /// 打开“隐私与安全性 - 辅助功能”设置页。
    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            print("[EditorIntegration] openAccessibilityPreferences")
            NSWorkspace.shared.open(url)
        }
    }

    /// 尝试从指定应用中读取当前文档的文件 URL。
    func currentFileURL(for app: EditorAppInfo) -> URL? {
        guard app.isInstalled else {
            print("[EditorIntegration] currentFileURL: app \(app.name) not installed")
            return nil
        }
        guard hasAccessibilityPermission else {
            print("[EditorIntegration] currentFileURL: no accessibility permission")
            return nil
        }

        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).first else {
            print("[EditorIntegration] currentFileURL: app \(app.name) not running")
            return nil
        }

        print("[EditorIntegration] currentFileURL: querying app \(app.name)")

        let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)

        // 1. 优先尝试获取聚焦窗口
        if let url = documentURL(fromAttribute: kAXFocusedWindowAttribute as String, of: axApp) {
            return url
        }

        // 2. 退而求其次，尝试主窗口
        if let url = documentURL(fromAttribute: kAXMainWindowAttribute as String, of: axApp) {
            return url
        }

        // 3. 尝试焦点元素本身
        if let url = documentURLFromFocusedElement(of: axApp) {
            return url
        }

        // 3. 最后遍历所有窗口，找到第一个带有文档路径的
        var windowsValue: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            axApp,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        if windowsError == .success,
           let array = windowsValue as? [Any] {
            for raw in array {
                let window = unsafeBitCast(raw as AnyObject, to: AXUIElement.self)
                if let url = documentURL(fromElement: window) {
                    return url
                }
            }
        }

        print("[EditorIntegration] currentFileURL: no AXDocument found for \(app.name)")

        // 4. 针对 Xcode 的兜底方案：
        //    4.1 先尝试通过 AppleScript 询问当前文档路径；
        //    4.2 若仍失败，则通过辅助功能读取编辑器文本，写入临时文件并返回该路径，
        //        至少保证“能拿到当前缓冲区内容做问答”，哪怕拿不到真实工程路径。
        if app.bundleIdentifier == "com.apple.dt.Xcode" {
            if let url = xcodeDocumentURLViaAppleScript() {
                return url
            }
            if let url = xcodeTemporaryFileURLViaAccessibility(appElement: axApp, runningApp: runningApp) {
                return url
            }
        }

        return nil
    }

    /// 组合 `EditorFileContext`，方便上层直接使用。
    func currentFileContext(for app: EditorAppInfo) -> EditorFileContext? {
        guard let url = currentFileURL(for: app) else {
            return nil
        }
        return EditorFileContext(app: app, fileURL: url)
    }

    // MARK: - Private helpers

    private func documentURL(fromAttribute attribute: String, of appElement: AXUIElement) -> URL? {
        var windowValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            attribute as CFString,
            &windowValue
        )

        guard error == .success, let rawWindow = windowValue else {
            return nil
        }

        let window = unsafeBitCast(rawWindow, to: AXUIElement.self)
        return documentURL(fromElement: window)
    }

    private func documentURL(fromElement element: AXUIElement) -> URL? {
        var documentValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXDocumentAttribute as CFString,
            &documentValue
        )

        guard error == .success, let path = documentValue as? String, !path.isEmpty else {
            if error == .success {
                print("[EditorIntegration] documentURL: empty kAXDocumentAttribute")
            } else {
                print("[EditorIntegration] documentURL: AX error \(error.rawValue)")
            }
            return nil
        }

        print("[EditorIntegration] documentURL: \(path)")
        return URL(fileURLWithPath: path)
    }

    private func documentURLFromFocusedElement(of appElement: AXUIElement) -> URL? {
        var focusedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )

        guard error == .success, let rawElement = focusedValue else {
            if error != .success {
                print("[EditorIntegration] focused element error \(error.rawValue)")
            }
            return nil
        }

        let element = unsafeBitCast(rawElement, to: AXUIElement.self)
        if let url = documentURL(fromElement: element) {
            return url
        }
        return documentURLByClimbingParents(from: element, depth: 0)
    }

    private func documentURLByClimbingParents(from element: AXUIElement, depth: Int) -> URL? {
        if depth > 6 {
            return nil
        }

        if let url = documentURL(fromElement: element) {
            return url
        }

        var parentValue: CFTypeRef?
        let parentError = AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentValue
        )

        guard parentError == .success, let rawParent = parentValue else {
            if parentError != .success {
                print("[EditorIntegration] parent error \(parentError.rawValue)")
            }
            return nil
        }

        let parent = unsafeBitCast(rawParent, to: AXUIElement.self)
        return documentURLByClimbingParents(from: parent, depth: depth + 1)
    }

    /// 当 Xcode 未暴露 AXDocument 且 AppleScript 也无法获取路径时，
    /// 尝试通过辅助功能遍历其窗口层级，找到代码编辑的文本区域，
    /// 读取文本内容写入沙盒临时目录，并返回该临时文件的 URL。
    private func xcodeTemporaryFileURLViaAccessibility(appElement: AXUIElement, runningApp: NSRunningApplication) -> URL? {
        // 优先使用聚焦窗口，其次主窗口，最后任意一个窗口。
        var candidateWindows: [AXUIElement] = []

        if let focusedWindow = element(fromAttribute: kAXFocusedWindowAttribute as String, of: appElement) {
            candidateWindows.append(focusedWindow)
        }
        if let mainWindow = element(fromAttribute: kAXMainWindowAttribute as String, of: appElement) {
            candidateWindows.append(mainWindow)
        }

        var windowsValue: CFTypeRef?
        let windowsError = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        if windowsError == .success,
           let array = windowsValue as? [Any] {
            // 避免重复加入已存在的 window 引用。
            for raw in array {
                let window = unsafeBitCast(raw as AnyObject, to: AXUIElement.self)
                if !candidateWindows.contains(where: { $0 === window }) {
                    candidateWindows.append(window)
                }
            }
        }

        guard !candidateWindows.isEmpty else {
            print("[EditorIntegration] Xcode text fallback: no window candidate")
            return nil
        }

        for window in candidateWindows {
            if let text = extractEditorText(fromWindow: window), !text.isEmpty {
                return writeTemporaryBufferFile(for: runningApp, text: text)
            }
        }

        print("[EditorIntegration] Xcode text fallback: failed to extract text from any window")
        return nil
    }

    /// 从给定的 AX 窗口节点中递归查找第一个代码编辑区域（AXTextArea / 文本字段），
    /// 返回其完整文本内容。
    private func extractEditorText(fromWindow window: AXUIElement) -> String? {
        return extractEditorTextRecursively(from: window, depth: 0)
    }

    private func extractEditorTextRecursively(from element: AXUIElement, depth: Int) -> String? {
        if depth > 8 {
            return nil
        }

        if let role = attributeString(kAXRoleAttribute as String, of: element),
           role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) {
            if let value = stringValue(of: element), !value.isEmpty {
                return value
            }
        }

        var childrenValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        guard error == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let text = extractEditorTextRecursively(from: child, depth: depth + 1) {
                return text
            }
        }

        return nil
    }

    /// 读取指定 AX 属性为 `AXUIElement`。
    private func element(fromAttribute attribute: String, of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        guard error == .success, let raw = value else {
            return nil
        }

        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    /// 读取指定 AX 属性为字符串。
    private func attributeString(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )

        guard error == .success, let string = value as? String else {
            return nil
        }

        return string
    }

    /// 读取文本类可访问元素的值，可处理 String / NSAttributedString 两种情况。
    private func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard error == .success, let value else {
            return nil
        }

        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    /// 将从 Xcode 文本编辑区读取到的内容写入沙盒临时目录，返回对应 URL。
    private func writeTemporaryBufferFile(for app: NSRunningApplication, text: String) -> URL? {
        let fileManager = FileManager.default
        let baseTempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("chatGLM-editor-buffers", isDirectory: true)

        do {
            try fileManager.createDirectory(at: baseTempDir, withIntermediateDirectories: true)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

            let rawName = app.localizedName ?? app.bundleIdentifier ?? "Editor"
            let sanitizedName = rawName.replacingOccurrences(of: " ", with: "_")
            let fileName = "\(sanitizedName)-buffer-\(timestamp).txt"

            let url = baseTempDir.appendingPathComponent(fileName)
            try text.write(to: url, atomically: true, encoding: .utf8)
            print("[EditorIntegration] Xcode text fallback: wrote buffer to \(url.path)")
            return url
        } catch {
            print("[EditorIntegration] Xcode text fallback: failed to write temp file: \(error.localizedDescription)")
            return nil
        }
    }

    /// 使用 AppleScript 向 Xcode 询问当前文档的 POSIX 路径。
    /// 该方法依赖系统的“自动化”权限，首次调用时系统会弹框询问是否允许 ChatGLM 控制 Xcode。
    private func xcodeDocumentURLViaAppleScript() -> URL? {
        let source = """
        tell application id "com.apple.dt.Xcode"
            if (count of documents) is 0 then
                return ""
            end if
            set theDoc to document 1
            set docPath to POSIX path of (path of theDoc)
            return docPath
        end tell
        """

        guard let script = NSAppleScript(source: source) else {
            print("[EditorIntegration] AppleScript: failed to create script")
            return nil
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            print("[EditorIntegration] AppleScript error: \(errorInfo)")
        }

        guard let path = result.stringValue, !path.isEmpty else {
            print("[EditorIntegration] AppleScript returned empty path")
            return nil
        }

        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[EditorIntegration] AppleScript document path: \(trimmed)")
        return URL(fileURLWithPath: trimmed)
    }
}

// MARK: - App picker sheet

/// 聊天输入框中选择应用时弹出的面板。
struct EditorAppPickerView: View {
    @ObservedObject var manager: EditorIntegrationManager
    var onSelect: (EditorAppInfo) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""

    private var filteredApps: [EditorAppInfo] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return manager.apps
        }
        return manager.apps.filter { app in
            app.name.localizedCaseInsensitiveContains(text)
                || app.bundleIdentifier.localizedCaseInsensitiveContains(text)
        }
    }

    private var primaryApps: [EditorAppInfo] {
        filteredApps.filter { $0.isConnectable && $0.isRunning }
    }

    private var secondaryApps: [EditorAppInfo] {
        filteredApps.filter { !primaryApps.contains($0) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                TextField("搜索应用", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom, 4)

            if !manager.hasAccessibilityPermission {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text("尚未授予辅助功能权限，可能无法获取编辑器中的文件。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("去设置") {
                        manager.openAccessibilityPreferences()
                    }
                    .font(.footnote)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.08))
                )
            }

            List {
                if !primaryApps.isEmpty {
                    Section(header: Text("使用应用")) {
                        ForEach(primaryApps) { app in
                            appRow(app: app)
                        }
                    }
                }

                if !secondaryApps.isEmpty {
                    Section(header: Text("其他应用")) {
                        ForEach(secondaryApps) { app in
                            appRow(app: app)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .onAppear {
                if !manager.hasAccessibilityPermission {
                    print("[EditorAppPickerView] onAppear -> requestAccessibilityPermission()")
                    manager.requestAccessibilityPermission()
                } else {
                    print("[EditorAppPickerView] onAppear -> refresh()")
                    manager.refresh()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 380)
    }

    private func appRow(app: EditorAppInfo) -> some View {
        Button {
            onSelect(app)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .cornerRadius(4)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 24, height: 24)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .foregroundStyle(.primary)
                    Text(app.bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Circle()
                    .fill(statusColor(for: app))
                    .frame(width: 8, height: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusColor(for app: EditorAppInfo) -> Color {
        guard app.isInstalled, app.hasAccessibilityPermission, app.isRunning else {
            return .gray.opacity(0.5)
        }
        return .green
    }
}

#endif
