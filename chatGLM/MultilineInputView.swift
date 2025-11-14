import SwiftUI

struct MultilineInputView: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        #if os(macOS)
        MacMultilineTextView(text: $text, onSend: onSend)
        #else
        IOSMultilineTextView(text: $text, onSend: onSend)
        #endif
    }
}

#if os(macOS)
private struct MacMultilineTextView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        let textView = SendingTextView()
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.drawsBackground = false
        textView.allowsUndo = true
        textView.onSend = {
            if !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onSend()
            }
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? SendingTextView,
           textView.string != text {
            textView.string = text
            textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacMultilineTextView

        init(_ parent: MacMultilineTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }

    class SendingTextView: NSTextView {
        var onSend: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 { // return
                if event.modifierFlags.contains(.shift) {
                    super.insertNewline(nil)
                } else {
                    onSend?()
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
#else
private struct IOSMultilineTextView: UIViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> CustomTextView {
        let textView = CustomTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.onSend = onSend
        return textView
    }

    func updateUIView(_ uiView: CustomTextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSMultilineTextView

        init(_ parent: IOSMultilineTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                parent.onSend()
                return false
            }
            return true
        }
    }

    class CustomTextView: UITextView {
        var onSend: (() -> Void)?

        override var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(sendCommand), discoverabilityTitle: "发送"),
                UIKeyCommand(input: "\r", modifierFlags: [.shift], action: #selector(insertNewlineCommand), discoverabilityTitle: "换行")
            ]
        }

        override var canBecomeFirstResponder: Bool { true }

        @objc private func sendCommand() {
            onSend?()
        }

        @objc private func insertNewlineCommand() {
            insertText("\n")
        }

    }
}
#endif
