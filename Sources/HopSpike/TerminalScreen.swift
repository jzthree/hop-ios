import SwiftUI
import SwiftTerm

// The spike's whole point: SwiftTerm's native TerminalView with the REAL iOS
// keyboard, attached to a live hop session. Native scroll physics, native
// text input, hardware keyboard support — the things Safari can't give us.
struct TerminalScreen: UIViewRepresentable {
    let url: String
    let room: String

    func makeCoordinator() -> Coordinator { Coordinator(url: url, room: room) }

    func makeUIView(context: Context) -> TerminalView {
        let tv = TerminalView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        tv.backgroundColor = .black
        tv.nativeForegroundColor = UIColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1)
        tv.nativeBackgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        context.coordinator.attach(view: tv)
        tv.becomeFirstResponder()
        return tv
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        private let client = HayClient()
        private weak var view: TerminalView?
        private let url: String
        private let room: String
        private var connectedOnce = false

        init(url: String, room: String) {
            self.url = url
            self.room = room
        }

        func attach(view: TerminalView) {
            self.view = view
            client.onEvent = { [weak self] event in
                guard let self, let tv = self.view else { return }
                switch event {
                case .connected:
                    break
                case .output(let data):
                    tv.feed(text: data)
                case .activeSize(let cols, let rows):
                    // Follow the shared size; SwiftTerm reflows the buffer.
                    if tv.getTerminal().cols != cols || tv.getTerminal().rows != rows {
                        tv.getTerminal().resize(cols: cols, rows: rows)
                    }
                case .ended(let message):
                    tv.feed(text: "\r\n\u{1b}[2m[\(message)]\u{1b}[0m\r\n")
                case .closed:
                    tv.feed(text: "\r\n\u{1b}[2m[disconnected]\u{1b}[0m\r\n")
                }
            }
            let t = view.getTerminal()
            client.connect(base: url, room: room, cols: t.cols, rows: t.rows)
            connectedOnce = true
        }

        func detach() { client.close() }

        // ── TerminalViewDelegate ──
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            if let text = String(bytes: data, encoding: .utf8) {
                client.sendInput(text)
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard connectedOnce else { return }
            client.sendResize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let u = URL(string: link) { UIApplication.shared.open(u) }
        }
        func clipboardCopy(source: TerminalView, content: Data) {
            if let s = String(data: content, encoding: .utf8) { UIPasteboard.general.string = s }
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
        func bell(source: TerminalView) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred() // native haptics, day one
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}
