import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""

    private let userDefaultsKey = "ZHIPU_API_KEY"
    private let unifiedKey = "ZhipuAPIKey"
    private let onClose: (() -> Void)?

    #if os(macOS)
    @State private var isManagingApps = false
    #endif

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        Group {
            #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            NavigationStack {
                formContent
                    .navigationTitle("设置")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { dismiss() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { saveAndDismiss() }
                        }
                    }
            }
            #elseif os(macOS)
            macOSLayout
            #else
            VStack {
                formContent
                HStack {
                    Spacer()
                    Button("取消") {
                        dismiss()
                    }
                    Button("完成") {
                        saveAndDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(minWidth: 420, minHeight: 220)
            #endif
        }
        .onAppear(perform: loadExistingKey)
    }

    private var formContent: some View {
        Form {
            Section(header: Text("智谱设置")) {
                SecureField("请输入智谱 API Key", text: $apiKey)

                Text("不会上传到服务器，仅保存在本机，用于调用智谱 GLM 接口。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if apiKey.isEmpty {
                    Text("当前未配置 API Key，默认仅能使用本地 UI。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("已配置 API Key，可正常调用对话、文生图与视频生成。")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func loadExistingKey() {
        if let stored = UserDefaults.standard.string(forKey: unifiedKey), !stored.isEmpty {
            apiKey = stored
        } else if let legacy = UserDefaults.standard.string(forKey: userDefaultsKey), !legacy.isEmpty {
            apiKey = legacy
        }
    }

    private func saveAndDismiss() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: unifiedKey)
        // 兼容老 key，顺便写一份
        UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        close()
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }
}

#if os(macOS)

private extension SettingsView {
    var macOSLayout: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置")
                .font(.title2.weight(.semibold))

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("使用应用")
                        .font(.headline)

                    Button {
                        isManagingApps = true
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.blue.opacity(0.12))
                                Image(systemName: "macwindow")
                                    .foregroundStyle(.blue)
                            }
                            .frame(width: 30, height: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("管理应用")
                                    .font(.subheadline)
                                Text("管理 Xcode、VSCode 等可连接的编辑器")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(maxHeight: 160)

                VStack(alignment: .leading, spacing: 10) {
                    Text("智谱设置")
                        .font(.headline)

                    SecureField("请输入智谱 API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)

                    Text("不会上传到服务器，仅保存在本机，用于调用智谱 GLM 接口。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if apiKey.isEmpty {
                        Text("当前未配置 API Key，默认仅能使用本地 UI。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("已配置 API Key，可正常调用对话、文生图与视频生成。")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("取消") {
                    close()
                }
                Button("完成") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 280)
        .sheet(isPresented: $isManagingApps) {
            AppManagementView()
        }
    }
}

struct AppManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = EditorIntegrationManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("管理应用")
                    .font(.title2.bold())
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Text("允许 ChatGLM 通过辅助功能访问以下应用，用于读取当前编辑的文件并提供代码修改建议。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if !manager.hasAccessibilityPermission {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("尚未授予辅助功能权限")
                            .font(.subheadline.bold())
                    }
                    Text("请在“系统设置 > 隐私与安全性 > 辅助功能”中勾选 ChatGLM，或点击下方按钮跳转设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button("打开辅助功能设置") {
                            manager.openAccessibilityPreferences()
                        }
                        Button("再次请求权限") {
                            manager.requestAccessibilityPermission()
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.yellow.opacity(0.08))
                )
            }

            List {
                Section(header: Text("关联的应用")) {
                    ForEach(manager.apps) { app in
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
                                Text(statusText(for: app))
                                    .font(.caption)
                                    .foregroundStyle(statusColor(for: app))
                            }

                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.inset)
            .onAppear {
                if !manager.hasAccessibilityPermission {
                    print("[AppManagementView] onAppear -> requestAccessibilityPermission()")
                    manager.requestAccessibilityPermission()
                } else {
                    print("[AppManagementView] onAppear -> refresh()")
                    manager.refresh()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
    }

    private func statusText(for app: EditorAppInfo) -> String {
        guard app.isInstalled else {
            return "未安装"
        }
        guard app.hasAccessibilityPermission else {
            return "缺少辅助功能权限，无法连接"
        }
        if app.isRunning {
            return "已通过可访问性使用"
        } else {
            return "应用未运行"
        }
    }

    private func statusColor(for app: EditorAppInfo) -> Color {
        guard app.isInstalled, app.hasAccessibilityPermission, app.isRunning else {
            return .secondary
        }
        return .green
    }
}
#endif
