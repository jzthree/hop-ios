import SwiftUI
import SwiftTerm

// Native terminal host: SwiftTerm view + a key accessory bar above the iOS
// keyboard (Esc / Tab / sticky-Ctrl / arrows / paste — the keys the soft
// keyboard lacks), connection-state chrome, and haptic bells.
struct TerminalHostView: View {
    @EnvironmentObject var model: AppModel
    let session: HopSession
    @State private var status: ConnState = .connecting
    enum ConnState { case connecting, live, closed }

    var body: some View {
        TerminalScreen(model: model, room: session.internalName, status: $status)
            .ignoresSafeArea(.container, edges: .bottom)
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Circle()
                        .fill(status == .live ? Color.green : status == .connecting ? Color.yellow : Color.red)
                        .frame(width: 10, height: 10)
                        .accessibilityLabel(status == .live ? "connected" : "disconnected")
                }
            }
            .onAppear { model.markSeen(session) }
            .background(Color.black)
    }
}

struct TerminalScreen: UIViewRepresentable {
    let model: AppModel
    let room: String
    @Binding var status: TerminalHostView.ConnState

    func makeCoordinator() -> Coordinator {
        Coordinator(wsBase: model.wsBase, urlSession: model.urlSession, room: room) { status = $0 }
    }

    func makeUIView(context: Context) -> HopTermView {
        let tv = HopTermView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        tv.keyHandler = context.coordinator
        tv.installAccessoryBar()
        tv.backgroundColor = .black
        tv.nativeForegroundColor = UIColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1)
        tv.nativeBackgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        context.coordinator.attach(view: tv)
        tv.becomeFirstResponder()
        return tv
    }

    func updateUIView(_ uiView: HopTermView, context: Context) {}

    static func dismantleUIView(_ uiView: HopTermView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate, AccessoryKeyHandler {
        private let client = HayClient()
        private weak var view: HopTermView?
        private let wsBase: String
        private let urlSession: URLSession
        private let room: String
        private let setStatus: (TerminalHostView.ConnState) -> Void
        private var ctrlArmed = false

        init(wsBase: String, urlSession: URLSession, room: String,
             setStatus: @escaping (TerminalHostView.ConnState) -> Void) {
            self.wsBase = wsBase
            self.urlSession = urlSession
            self.room = room
            self.setStatus = setStatus
        }

        func attach(view: HopTermView) {
            self.view = view
            client.onEvent = { [weak self] event in
                guard let self, let tv = self.view else { return }
                switch event {
                case .connected:
                    self.setStatus(.live)
                case .output(let data):
                    tv.feed(text: data)
                case .activeSize(let cols, let rows):
                    if tv.getTerminal().cols != cols || tv.getTerminal().rows != rows {
                        tv.getTerminal().resize(cols: cols, rows: rows)
                    }
                case .ended(let message):
                    self.setStatus(.closed)
                    tv.feed(text: "\r\n\u{1b}[2m[\(message)]\u{1b}[0m\r\n")
                case .closed:
                    self.setStatus(.closed)
                    tv.feed(text: "\r\n\u{1b}[2m[disconnected — go back and reopen]\u{1b}[0m\r\n")
                }
            }
            let t = view.getTerminal()
            client.connect(base: wsBase, room: room, cols: t.cols, rows: t.rows, using: urlSession)
        }

        func detach() { client.close() }

        // ── AccessoryKeyHandler ──
        func accessoryKey(_ key: AccessoryKey) {
            switch key {
            case .esc: client.sendInput("\u{1b}")
            case .tab: client.sendInput("\t")
            case .ctrl:
                ctrlArmed.toggle()
                view?.setCtrlArmed(ctrlArmed)
            case .up: client.sendInput("\u{1b}[A")
            case .down: client.sendInput("\u{1b}[B")
            case .left: client.sendInput("\u{1b}[D")
            case .right: client.sendInput("\u{1b}[C")
            case .paste:
                if let s = UIPasteboard.general.string { client.sendInput(s) }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // ── TerminalViewDelegate ──
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard var text = String(bytes: data, encoding: .utf8) else { return }
            if ctrlArmed, let scalar = text.unicodeScalars.first, text.count == 1,
               scalar.isASCII, scalar.value >= 0x40 {
                text = String(UnicodeScalar(scalar.value & 0x1f)!)
                ctrlArmed = false
                view?.setCtrlArmed(false)
            }
            client.sendInput(text)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
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
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}

// ── Accessory key bar ──
enum AccessoryKey { case esc, tab, ctrl, up, down, left, right, paste }
protocol AccessoryKeyHandler: AnyObject { func accessoryKey(_ key: AccessoryKey) }

final class HopTermView: TerminalView {
    weak var keyHandler: AccessoryKeyHandler?
    private var ctrlButton: UIButton?

    // SwiftTerm exposes inputAccessoryView as a settable var — assign, don't override.
    func installAccessoryBar() {
        inputAccessoryView = makeAccessory()
    }

    func setCtrlArmed(_ armed: Bool) {
        ctrlButton?.configuration?.baseForegroundColor = armed ? .black : .white
        ctrlButton?.configuration?.background.backgroundColor =
            armed ? UIColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1) : UIColor(white: 0.22, alpha: 1)
    }

    private func makeAccessory() -> UIView {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        bar.backgroundColor = UIColor(white: 0.11, alpha: 1)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -5)
        ])
        let keys: [(String, AccessoryKey)] = [
            ("esc", .esc), ("tab", .tab), ("ctrl", .ctrl),
            ("←", .left), ("↓", .down), ("↑", .up), ("→", .right), ("⌘V", .paste)
        ]
        for (label, key) in keys {
            var cfg = UIButton.Configuration.filled()
            cfg.title = label
            cfg.baseForegroundColor = .white
            cfg.background.backgroundColor = UIColor(white: 0.22, alpha: 1)
            cfg.background.cornerRadius = 8
            cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .medium)
                return out
            }
            let btn = UIButton(configuration: cfg, primaryAction: UIAction { [weak self] _ in
                self?.keyHandler?.accessoryKey(key)
            })
            if key == .ctrl { ctrlButton = btn }
            stack.addArrangedSubview(btn)
        }
        return bar
    }
}
