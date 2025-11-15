import SwiftUI
import SwiftData
#if canImport(PhotosUI)
import PhotosUI
#endif
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
import Carbon.HIToolbox
#endif
import MarkdownUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse)
    private var conversations: [ConversationRecord]

    @StateObject private var viewModel = ChatViewModel.shared
    @State private var selectedConversation: ConversationRecord?
    @Namespace private var animationNamespace

    var body: some View {
        ZStack {
            BackgroundGradientView()
                .ignoresSafeArea()

            #if os(macOS)
            NavigationSplitView {
                sidebar
            } detail: {
                chatArea
            }
            .navigationSplitViewStyle(.balanced)
            #else
            GeometryReader { proxy in
                let isLandscape = proxy.size.width > proxy.size.height

                #if os(iOS)
                let isPad = UIDevice.current.userInterfaceIdiom == .pad

                Group {
                    if isPad && isLandscape {
                        NavigationSplitView {
                            sidebar
                        } detail: {
                            chatArea
                        }
                        .navigationSplitViewStyle(.balanced)
                    } else {
                        NavigationStack {
                            iosConversationList
                        }
                    }
                }
                #else
                NavigationStack {
                    iosConversationList
                }
                #endif
            }
            #endif
        }
        .onAppear {
            if selectedConversation == nil {
                if let first = conversations.first {
                    selectConversation(first)
                } else {
                    createNewConversation()
                }
            }
        }
#if !os(macOS)
        .sheet(item: $activeSheet) { item in
            switch item {
            case .settings:
                SettingsView()
            }
        }
#endif
    }

    #if !os(macOS)
    private var iosConversationList: some View {
        List {
            Section {
                Button {
                    createNewConversation()
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                        Text("新建对话")
                    }
                }
            }

            Section(header: Text("历史对话")) {
                ForEach(conversations) { conversation in
                    NavigationLink {
                        chatArea
                            .onAppear {
                                selectConversation(conversation)
                            }
                    } label: {
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.secondary)
                            Text(conversation.title.isEmpty ? "新会话" : conversation.title)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteConversation(conversation)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("会话")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置智谱 API Key")
                }
            }
    }
    #endif

    private var sidebarSelection: Binding<UUID?> {
        Binding(
            get: { selectedConversation?.id },
            set: { newValue in
                guard let id = newValue else {
                    selectedConversation = nil
                    viewModel.messages = []
                    return
                }

                if let conversation = conversations.first(where: { $0.id == id }) {
                    selectConversation(conversation)
                }
            }
        )
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // 顶部搜索与空间切换
            VStack(alignment: .leading, spacing: 12) {
                TextField("搜索", text: .constant(""))
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 4) {
                    Label("ChatGLM", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                    Label("GLM 工具", systemImage: "wand.and.stars")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List(selection: sidebarSelection) {
                HStack {
                    Text("新建对话")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        createNewConversation()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(conversations) { conversation in
                    HStack {
                        Image(systemName: "message.fill")
                            .foregroundStyle(.secondary)
                        Text(conversation.title.isEmpty ? "新会话" : conversation.title)
                            .lineLimit(1)
                        Spacer()
                    }
                    .tag(conversation.id)
                    .contentShape(Rectangle())
                    .listRowBackground(
                        (conversation.id == selectedConversation?.id ? Color.white.opacity(0.06) : .clear)
                            .background(Color.clear)
                    )
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteConversation(conversation)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Spacer()

            // 底部账号区域
            HStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.green.opacity(0.8), Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text("J")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("JACKSON WANG")
                        .font(.footnote.weight(.semibold))
                    Text("免费计划")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                #if os(macOS)
                Button {
                    SettingsWindowController.shared.show()
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #else
                Button {
                    activeSheet = .settings
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                #endif
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Group {
                    if colorScheme == .dark {
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        LinearGradient(
                            colors: [Color.black.opacity(0.0), Color.black.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            )
        }
        .background(
            Group {
                if colorScheme == .dark {
                    LinearGradient(
                        colors: [
                            Color(red: 18/255, green: 19/255, blue: 23/255),
                            Color(red: 10/255, green: 12/255, blue: 28/255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 245/255, green: 246/255, blue: 250/255),
                            Color(red: 230/255, green: 232/255, blue: 242/255)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        )
    }

    private enum ActiveSheet: Identifiable {
        case settings

        var id: Int { hashValue }
    }

    @State private var activeSheet: ActiveSheet?

    private var chatArea: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Divider()
                .foregroundColor(Color.white.opacity(0.08))

            ChatMessagesScrollView(
                messages: viewModel.messages,
                animationNamespace: animationNamespace
            )
            .onChange(of: viewModel.messages) { _, _ in
                persistCurrentConversation()
            }

            Divider()
                .foregroundColor(Color.white.opacity(0.08))

            RainbowGlowInputBar(
                text: $viewModel.inputText,
                isSending: viewModel.isSending,
                selectedImageData: $viewModel.selectedImageData,
                selectedFileSummary: $viewModel.selectedFileSummary,
                selectedFileName: $viewModel.selectedFileName,
                selectedFileURL: $viewModel.selectedFileURL,
                onSend: {
                    viewModel.sendCurrentInput()
                    persistCurrentConversation()
                },
                onCancel: {
                    viewModel.cancelCurrentRequest()
                }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
        }
        .background(
            Group {
                if colorScheme == .dark {
                    Color(red: 20/255, green: 21/255, blue: 25/255)
                } else {
                    Color(red: 244/255, green: 245/255, blue: 250/255)
                }
            }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(ChatMode.allCases) { mode in
                    Button {
                        viewModel.mode = mode
                    } label: {
                        if viewModel.mode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("chatGLM")
                        .font(.title3.weight(.semibold))
                    Text(viewModel.mode.title)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }

            Spacer()

            Button {
                // 升级按钮占位
            } label: {
                Text("+ 升级套餐")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.purple.opacity(0.35))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Conversation helpers

    private func deleteConversation(_ conversation: ConversationRecord) {
        if selectedConversation?.id == conversation.id {
            selectedConversation = nil
            viewModel.messages = []
        }

        modelContext.delete(conversation)

        do {
            try modelContext.save()
        } catch {
            // ignore for now
        }

        if selectedConversation == nil, let first = conversations.first {
            selectConversation(first)
        }
    }

    private func selectConversation(_ conversation: ConversationRecord) {
        selectedConversation = conversation
        loadMessages(from: conversation)
    }

    private func createNewConversation() {
        let conversation = ConversationRecord(title: "新会话")
        modelContext.insert(conversation)
        selectedConversation = conversation
        viewModel.messages = []
        viewModel.inputText = ""
        persistCurrentConversation()
    }

    private func loadMessages(from conversation: ConversationRecord) {
        let sortedMessages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        viewModel.messages = sortedMessages.map { record in
            let sender: ChatSender = record.sender == "user" ? .user : .assistant
            let imageURLs = record.imageURLs.compactMap { URL(string: $0) }
            let videoURL = record.videoURL.flatMap { URL(string: $0) }
            return ChatMessage(
                sender: sender,
                text: record.text,
                createdAt: record.createdAt,
                isStreaming: false,
                isLoadingPending: record.isLoadingPending,
                imageURLs: imageURLs,
                videoURL: videoURL,
                attachedImageData: record.attachedImageData,
                attachedFileName: record.attachedFileName,
                reasoning: record.reasoning
            )
        }
    }

    private func persistCurrentConversation() {
        guard let conversation = selectedConversation else {
            return
        }

        // 清理原有消息并重新映射
        conversation.messages.removeAll()

        let records: [MessageRecord] = viewModel.messages.map { message in
            let senderString = message.sender == .user ? "user" : "assistant"
            let imageURLStrings = message.imageURLs.map { $0.absoluteString }
            let videoURLString = message.videoURL?.absoluteString

            return MessageRecord(
                sender: senderString,
                text: message.text,
                createdAt: message.createdAt,
                imageURLs: imageURLStrings,
                videoURL: videoURLString,
                attachedImageData: message.attachedImageData,
                attachedFileName: message.attachedFileName,
                reasoning: message.reasoning,
                isLoadingPending: message.isLoadingPending
            )
        }

        for record in records {
            modelContext.insert(record)
        }
        conversation.messages = records
        conversation.updatedAt = Date()
        conversation.title = makeTitle(for: conversation, messages: viewModel.messages)

        enforceStorageLimit()

        do {
            try modelContext.save()
        } catch {
            // 在 UI 层暂时静默错误，实际项目可加日志
        }
    }

    private func makeTitle(for conversation: ConversationRecord, messages: [ChatMessage]) -> String {
        if let first = messages.first(where: { $0.sender == .user }) {
            let trimmed = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "新会话"
            }
            if trimmed.count > 18 {
                let index = trimmed.index(trimmed.startIndex, offsetBy: 18)
                return String(trimmed[..<index]) + "…"
            }
            return trimmed
        }
        return "新会话"
    }

    private func enforceStorageLimit() {
        let maxBytes = 100 * 1024 * 1024

        let fetchDescriptor = FetchDescriptor<ConversationRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )

        guard let allConversations = try? modelContext.fetch(fetchDescriptor) else {
            return
        }

        func approximateSize(of message: MessageRecord) -> Int {
            let textBytes = message.text.utf8.count
            let imageBytes = message.imageURLs.reduce(0) { $0 + $1.utf8.count }
            let videoBytes = message.videoURL?.utf8.count ?? 0
            let attachmentBytes = message.attachedImageData?.count ?? 0
            return textBytes + imageBytes + videoBytes + attachmentBytes + 128
        }

        var totalBytes = allConversations.reduce(0) { partial, conversation in
            partial + conversation.messages.reduce(0) { $0 + approximateSize(of: $1) }
        }

        guard totalBytes > maxBytes else {
            return
        }

        for conversation in allConversations {
            let conversationBytes = conversation.messages.reduce(0) { $0 + approximateSize(of: $1) }
            modelContext.delete(conversation)
            totalBytes -= conversationBytes
            if totalBytes <= maxBytes {
                break
            }
        }
    }
}

#Preview {
    ContentView()
}

struct BackgroundGradientView: View {
    @State private var animate = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                Color(red: 14/255, green: 15/255, blue: 19/255)
            } else {
                Color(red: 242/255, green: 244/255, blue: 250/255)
            }
        }
    }
}

struct ChatMessagesScrollView: View {
    let messages: [ChatMessage]
    var animationNamespace: Namespace.ID

    var body: some View {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubbleView(message: message, animationNamespace: animationNamespace)
                            .id(message.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: messages) { _, _ in
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    var animationNamespace: Namespace.ID
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.sender == .assistant {
                avatar
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: message.sender == .assistant ? .leading : .trailing, spacing: 8) {
                if let reasoning = message.reasoning,
                   !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   message.sender == .assistant {
                    ReasoningCardView(text: reasoning)
                }

                Group {
                    if message.sender == .assistant {
                        Markdown(message.text)
                            .markdownTheme(.chatBubble)
                            .padding(12)
                    } else {
                        Markdown(message.text)
                            .markdownTheme(.chatBubble)
                            .padding(12)
                    }
                }
                .background(
                    bubbleBackground
                        .matchedGeometryEffect(id: "bubble-\(message.id)", in: animationNamespace)
                )
                .overlay(
                    message.isStreaming
                    ? AnyView(
                        ShimmerView()
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
                    : AnyView(EmptyView())
                )

                if message.isLoadingPending {
                    LoadingIndicatorView()
                }

                if let data = message.attachedImageData {
                    AttachedImagePreview(data: data)
                }

                if !message.imageURLs.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(message.imageURLs, id: \.self) { url in
                                GeneratedImageView(url: url)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }

                if let videoURL = message.videoURL {
                    GeneratedVideoPlaceholderView(url: videoURL)
                }
            }

            if message.sender == .user {
                avatar
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 4)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(message.sender == .assistant ? Color.blue.opacity(0.25) : Color.green.opacity(0.25))
            Image(systemName: message.sender == .assistant ? "sparkles" : "person.circle.fill")
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .shadow(radius: 4, x: 0, y: 2)
    }

    private var bubbleBackground: some View {
        let baseColor: Color

        if message.sender == .assistant {
            if colorScheme == .dark {
                baseColor = Color.white.opacity(0.06)
            } else {
                baseColor = Color.white
            }
        } else {
            if colorScheme == .dark {
                baseColor = Color.blue.opacity(0.45)
            } else {
                baseColor = Color.blue.opacity(0.15)
            }
        }

        return RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(baseColor)
    }
}

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        LinearGradient(
            gradient: Gradient(
                colors: [
                    .white.opacity(0.0),
                    .white.opacity(0.5),
                    .white.opacity(0.0)
                ]
            ),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .blendMode(.screen)
        .opacity(0.8)
        .mask(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.black.opacity(0), .black, .black.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: phase)
        )
        .onAppear {
            withAnimation(
                .linear(duration: 1.4)
                .repeatForever(autoreverses: false)
            ) {
                phase = 200
            }
        }
    }
}

extension Theme {
    static var chatBubble: Theme {
        Theme()
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .font(Font.system(.body, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.gray.opacity(0.15))
                        )
                }
            }
    }
}

struct GeneratedImageView: View {
    let url: URL

    var body: some View {
        VStack {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 120, height: 120)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                case .failure:
                    Image(systemName: "photo")
                        .frame(width: 120, height: 120)
                        .background(Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

struct GeneratedVideoPlaceholderView: View {
    let url: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 28)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("视频已生成")
                    .font(.subheadline.weight(.semibold))
                Text(url.absoluteString)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.4))
        )
    }
}

struct AttachedImagePreview: View {
    let data: Data

    var body: some View {
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        #elseif os(macOS)
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        #else
        EmptyView()
        #endif
    }
}

struct ReasoningCardView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("推理过程")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 64)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

struct LoadingIndicatorView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
            Text("生成中...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

struct RainbowGlowInputBar: View {
    @Binding var text: String
    var isSending: Bool
    @Binding var selectedImageData: Data?
    @Binding var selectedFileSummary: String?
    @Binding var selectedFileName: String?
    @Binding var selectedFileURL: URL?
    var onSend: () -> Void
    var onCancel: () -> Void

    @State private var glowRotation: Double = 0
    @FocusState private var isFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    #if canImport(PhotosUI)
    @State private var photoItem: PhotosPickerItem?
    #endif
    @State private var showFileImporter = false

    #if os(macOS)
    @State private var showAppPicker = false
    @StateObject private var editorManager = EditorIntegrationManager()
    #endif

    var body: some View {
        VStack(spacing: 6) {
            if let name = selectedFileName, let summary = selectedFileSummary, !summary.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        clearFileContext()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            colorScheme == .dark
                            ? Color.white.opacity(0.04)
                            : Color.gray.opacity(0.12)
                        )
                )
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        colorScheme == .dark
                        ? Color.white.opacity(0.05)
                        : Color.gray.opacity(0.12)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                AngularGradient(
                                    gradient: Gradient(colors: [
                                        .red, .orange, .yellow, .green, .blue, .purple, .pink, .red
                                    ]),
                                    center: .center
                                ),
                                lineWidth: (isFocused || !text.isEmpty) ? 2.0 : 0.8
                            )
                            .blur(radius: (isFocused || !text.isEmpty) ? 4 : 2)
                            .opacity(isFocused || !text.isEmpty ? 0.9 : 0.3)
                            .hueRotation(.degrees(glowRotation))
                    )
                    .animation(
                        .linear(duration: 6)
                        .repeatForever(autoreverses: false),
                        value: glowRotation
                    )

                VStack(spacing: 4) {
                    // 输入区域：最多 3 行，超出后内部可滚动
                    MultilineInputView(text: $text, onSend: performSend)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .frame(minHeight: 36)
                        .focused($isFocused)

                    HStack(spacing: 14) {
                        attachmentMenu

                        #if os(macOS)
                        Button {
                            showAppPicker = true
                        } label: {
                            Image(systemName: "macwindow")
                                .foregroundStyle(.secondary)
                        }
                        #endif

                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Image(systemName: "character.book.closed")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "mic")
                            .foregroundStyle(.secondary)

                        if isSending {
                            Button(action: onCancel) {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                        } else {
                            Button(action: performSend) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .disabled(trimmedText.isEmpty)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
            .frame(minHeight: 56, maxHeight: 110, alignment: .top)
            .onAppear {
                glowRotation = 0
                withAnimation(
                    .linear(duration: 6)
                    .repeatForever(autoreverses: false)
                ) {
                    glowRotation = 360
                }
            }
        }
        #if os(macOS)
        .sheet(isPresented: $showAppPicker) {
            EditorAppPickerView(manager: editorManager) { app in
                if let context = editorManager.currentFileContext(for: app) {
                    Task {
                        await loadFileContext(from: context.fileURL)
                    }
                } else {
                    // 获取失败时，在文件摘要区域给出提示，方便用户手动调整。
                    let name = app.name
                    Task { @MainActor in
                        selectedFileName = name
                        selectedFileSummary = "未能从 \(name) 获取当前文件，请确认该应用中已打开一个文档，并在“系统设置 > 隐私与安全性 > 辅助功能”中为 ChatGLM 启用权限。"
                    }
                }
            }
        }
        #endif
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performSend() {
        guard !trimmedText.isEmpty else { return }
        onSend()
    }

    private func clearFileContext() {
        selectedFileName = nil
        selectedFileSummary = nil
        selectedFileURL = nil
    }

    private var attachmentMenu: some View {
        #if canImport(PhotosUI)
        Menu {
            PhotosPicker(selection: Binding(
                get: { photoItem },
                set: { newValue in
                    photoItem = newValue
                    Task {
                        if let data = try? await newValue?.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                selectedImageData = data
                            }
                        }
                    }
                }
            )) {
                Label("添加图片", systemImage: "photo")
            }

            Button {
                showFileImporter = true
            } label: {
                Label("选择文件", systemImage: "doc")
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await loadFileContext(from: url)
                }
            case .failure:
                break
            }
        }
        #else
        Menu {
            Button("选择文件") {
                showFileImporter = true
            }
        } label: {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await loadFileContext(from: url)
                }
            case .failure:
                break
            }
        }
        #endif
    }

    private func loadFileContext(from url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent

            if let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let maxLength = 2000
                let snippet: String
                if trimmed.count > maxLength {
                    let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
                    snippet = String(trimmed[..<index]) + "…"
                } else {
                    snippet = trimmed
                }

                await MainActor.run {
                    selectedFileName = fileName
                    selectedFileSummary = snippet
                    selectedFileURL = url
                }
            } else {
                let sizeKB = max(1, data.count / 1024)
                await MainActor.run {
                    selectedFileName = fileName
                    selectedFileSummary = "非纯文本文件，大小约 \(sizeKB) KB。"
                    selectedFileURL = url
                }
            }
        } catch {
            await MainActor.run {
                selectedFileName = url.lastPathComponent
                selectedFileSummary = "读取文件失败：\(error.localizedDescription)"
                selectedFileURL = url
            }
        }
    }
}

#if os(macOS)
struct QuickInputView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    init(viewModel: ChatViewModel = .shared) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("快速提问")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("输入你的问题…", text: $text, onCommit: commit)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)

            HStack {
                Spacer()
                Button("取消") {
                    QuickInputPanelController.shared.close()
                }
                Button("发送") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 420)
        .onAppear {
            isFocused = true
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        guard !trimmed.isEmpty else {
            QuickInputPanelController.shared.close()
            return
        }

        viewModel.sendFromQuickInputPanel(text: trimmed)
        QuickInputPanelController.shared.close()
        bringMainWindowToFront()
    }

    private func bringMainWindowToFront() {
        guard let window = NSApplication.shared.windows.first(where: { !($0 is NSPanel) }) else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

final class QuickInputPanelController {
    static let shared = QuickInputPanelController()

    private var panel: NSPanel?

    private init() {}

    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let contentView = QuickInputView()
            let hosting = NSHostingController(rootView: contentView)

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 120),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.contentViewController = hosting
            panel.isReleasedWhenClosed = false

            self.panel = panel
        }

        guard let panel else { return }

        if let screen = NSScreen.main {
            let size = panel.frame.size
            let x = screen.frame.midX - size.width / 2
            let y = screen.frame.midY - size.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }
}

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    func register() {
        unregister()

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(UInt32(truncatingIfNeeded: 1))
        hotKeyID.id = 1

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr, hotKeyID.id == 1 {
                DispatchQueue.main.async {
                    QuickInputPanelController.shared.toggle()
                }
            }

            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else {
            print("GlobalHotKeyManager: InstallEventHandler failed with status \(status)")
            return
        }

        let keyCode = UInt32(kVK_ANSI_R)
        let modifiers = UInt32(optionKey)

        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus != noErr {
            print("GlobalHotKeyManager: RegisterEventHotKey failed with status \(registerStatus)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}
#endif
