import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""

    private let userDefaultsKey = "ZHIPU_API_KEY"
    private let unifiedKey = "ZhipuAPIKey"

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
            Section(header: Text("智谱 API Key")) {
                SecureField("请输入 API Key", text: $apiKey)

                Text("不会上传到服务器，仅保存在本机，用于调用智谱 GLM 接口。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
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
        dismiss()
    }
}
