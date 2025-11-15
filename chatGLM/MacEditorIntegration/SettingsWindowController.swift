import SwiftUI

#if os(macOS)
import AppKit

/// 管理独立的「设置」窗口，仅在 macOS 使用。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = SettingsView(onClose: { [weak self] in
                print("[SettingsWindowController] onClose from SettingsView")
                self?.close()
            })
            let hosting = NSHostingController(rootView: root)

            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 320),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = "设置"
            newWindow.isReleasedWhenClosed = false
            newWindow.contentViewController = hosting
            newWindow.center()
            newWindow.delegate = self

            window = newWindow
        }

        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let window else { return }
        window.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        print("[SettingsWindowController] windowWillClose")
        window = nil
    }
}
#endif

