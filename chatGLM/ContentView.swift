import SwiftUI
import SwiftData
#if canImport(PhotosUI)
import PhotosUI
#endif
#if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse)
    private var conversations: [ConversationRecord]

    @StateObject private var viewModel = ChatViewModel()
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
            NavigationStack {
                chatArea
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

            // 会话列表占位
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
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
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    ForEach(conversations) { conversation in
                        HStack {
                            Image(systemName: "message.fill")
                                .foregroundStyle(.secondary)
                            Text(conversation.title.isEmpty ? "新会话" : conversation.title)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(conversation.id == selectedConversation?.id ? Color.white.opacity(0.06) : .clear)
                        )
                        .onTapGesture {
                            selectConversation(conversation)
                        }
                    }
                }
                .padding(.bottom, 12)
            }

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

                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 18/255, green: 19/255, blue: 23/255),
                    Color(red: 10/255, green: 12/255, blue: 28/255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

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
            .onChange(of: viewModel.messages.count) { _ in
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
                onSend: {
                    viewModel.sendCurrentInput()
                    persistCurrentConversation()
                }
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(
            Color(red: 20/255, green: 21/255, blue: 25/255)
        )
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("chatGLM")
                    .font(.title3.weight(.semibold))

                Text(">")
                    .font(.headline)
                    .foregroundStyle(.secondary)

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

            HStack {
                Spacer()
                modePicker
                    .frame(maxWidth: 320)
                Spacer()
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: $viewModel.mode) {
            ForEach(ChatMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Conversation helpers

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
                imageURLs: imageURLs,
                videoURL: videoURL,
                attachedImageData: record.attachedImageData,
                attachedFileName: record.attachedFileName
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
                attachedFileName: message.attachedFileName
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

    var body: some View {
        Color(red: 14/255, green: 15/255, blue: 19/255)
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
            .background(Color.black.opacity(0.25))
            .onChange(of: messages.count) { _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage
    var animationNamespace: Namespace.ID

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if message.sender == .assistant {
                avatar
            } else {
                Spacer(minLength: 0)
            }

            VStack(alignment: message.sender == .assistant ? .leading : .trailing, spacing: 8) {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(12)
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
        Group {
            if message.sender == .assistant {
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.9),
                        Color.purple.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
            } else {
                LinearGradient(
                    colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.5)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

struct RainbowGlowInputBar: View {
    @Binding var text: String
    var isSending: Bool
    @Binding var selectedImageData: Data?
    @Binding var selectedFileSummary: String?
    @Binding var selectedFileName: String?
    var onSend: () -> Void

    @State private var glowRotation: Double = 0
    @FocusState private var isFocused: Bool

    #if canImport(PhotosUI)
    @State private var photoItem: PhotosPickerItem?
    #endif
    @State private var showFileImporter = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
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

                VStack(spacing: 6) {
                    // 输入区域：最多 3 行，超出后内部可滚动
                    TextField("询问任何问题", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .focused($isFocused)

                    HStack(spacing: 16) {
                        attachmentMenu

                        // 预留其它按钮位（示例：全球、火箭、翻译）
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        Image(systemName: "paperclip")
                            .foregroundStyle(.secondary)
                        Image(systemName: "character.book.closed")
                            .foregroundStyle(.secondary)

                        Spacer()

                        Image(systemName: "mic")
                            .foregroundStyle(.secondary)

                        Button(action: onSend) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                Image(systemName: isSending ? "hourglass" : "waveform")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
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
                }
            } else {
                let sizeKB = max(1, data.count / 1024)
                await MainActor.run {
                    selectedFileName = fileName
                    selectedFileSummary = "非纯文本文件，大小约 \(sizeKB) KB。"
                }
            }
        } catch {
            await MainActor.run {
                selectedFileName = url.lastPathComponent
                selectedFileSummary = "读取文件失败：\(error.localizedDescription)"
            }
        }
    }
}
