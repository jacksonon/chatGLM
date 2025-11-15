import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct chatGLMApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            ConversationRecord.self,
            MessageRecord.self
        ])
        let fileManager = FileManager.default
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let storeURL = supportURL.appendingPathComponent("chatGLMData.store")

        let configuration = ModelConfiguration("ChatStore", schema: schema, url: storeURL)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 如果本地旧数据与模型不兼容，删除旧存储后重建，避免启动崩溃
            try? fileManager.removeItem(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

#if os(macOS)
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        GlobalHotKeyManager.shared.register()
    }
}
#endif
