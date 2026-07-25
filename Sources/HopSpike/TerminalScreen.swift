import SwiftUI
import SwiftTerm

// Native terminal host: SwiftTerm view + a key accessory bar above the iOS
// keyboard (Esc / Tab / sticky-Ctrl / arrows / paste — the keys the soft
// keyboard lacks), connection-state chrome, and haptic bells.
struct TerminalHostView: View {
    @EnvironmentObject var model: AppModel
    let session: HopSession
    @State private var status: ConnState = .connecting
    @State private var fontSize: Double = UserDefaults.standard.double(forKey: "termFontSize") == 0 ? 12 : UserDefaults.standard.double(forKey: "termFontSize")
    @State private var lightTheme = UserDefaults.standard.bool(forKey: "termLight")
    @State private var findText = ""
    @State private var findOpen = false
    @State private var reconnectToken = 0
    @State private var toast: String?
    @Environment(\.scenePhase) private var scenePhase
    enum ConnState { case connecting, live, closed }

    private func setFont(_ size: Double) {
        fontSize = min(24, max(8, size))
        UserDefaults.standard.set(fontSize, forKey: "termFontSize")
    }

    var body: some View {
        TerminalScreen(model: model, room: session.internalName, status: $status,
                       fontSize: fontSize, lightTheme: lightTheme,
                       findText: findOpen ? findText : nil, reconnectToken: reconnectToken,
                       onToast: { toast = $0 })
            .padding(.horizontal, 5)
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .top) {
                if let toast {
                    Text(toast)
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 6)
                        .task { try? await Task.sleep(for: .seconds(2)); self.toast = nil }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if findOpen {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("find in scrollback", text: $findText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                        Button("Done") { findOpen = false; findText = "" }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(white: 0.12))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(white: 0.07), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(status == .live ? Color.green : status == .connecting ? Color.yellow : Color.red)
                            .frame(width: 8, height: 8)
                        Text(session.name)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        if !session.runningApp.isEmpty {
                            Text(session.runningApp)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.hopPurple.opacity(0.22), in: Capsule())
                                .foregroundStyle(Color.hopGlow)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { findOpen.toggle() } label: { Label("Find", systemImage: "magnifyingglass") }
                        Button { NotificationCenter.default.post(name: .hopCopyScreen, object: nil) } label: {
                            Label("Copy screen", systemImage: "doc.on.doc")
                        }
                        Button { NotificationCenter.default.post(name: .hopCopyAll, object: nil) } label: {
                            Label("Copy all scrollback", systemImage: "doc.on.clipboard")
                        }
                        Divider()
                        Button { setFont(fontSize + 1) } label: { Label("Bigger text", systemImage: "textformat.size.larger") }
                        Button { setFont(fontSize - 1) } label: { Label("Smaller text", systemImage: "textformat.size.smaller") }
                        Button {
                            lightTheme.toggle()
                            UserDefaults.standard.set(lightTheme, forKey: "termLight")
                        } label: {
                            Label(lightTheme ? "Dark terminal" : "Light terminal",
                                  systemImage: lightTheme ? "moon.fill" : "sun.max.fill")
                        }
                        Divider()
                        Button { reconnectToken += 1 } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // iOS suspends the socket when the app backgrounds; coming back
                // to a dead terminal and having to hunt for a menu item was the
                // single most annoying part of using this on a phone.
                if phase == .active, status != .live { reconnectToken += 1 }
            }
            .onAppear { model.markSeen(session) }
            .background(Color.black)
    }
}

extension Notification.Name {
    static let hopCopyScreen = Notification.Name("hopCopyScreen")
    static let hopCopyAll = Notification.Name("hopCopyAll")
}

struct TerminalScreen: UIViewRepresentable {
    let model: AppModel
    let room: String
    @Binding var status: TerminalHostView.ConnState
    var fontSize: Double = 12
    var lightTheme = false
    var findText: String?
    var reconnectToken = 0
    var onToast: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(wsBase: model.wsBase, httpBase: model.serverURL, token: model.accessToken,
                    urlSession: model.urlSession, room: room, onToast: onToast) { status = $0 }
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

    func updateUIView(_ uiView: HopTermView, context: Context) {
        uiView.font = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        uiView.applyTheme(light: lightTheme)
        if let findText, !findText.isEmpty { uiView.scrollToMatch(findText) }
        context.coordinator.reconnectIfNeeded(token: reconnectToken, view: uiView)
    }

    static func dismantleUIView(_ uiView: HopTermView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate, AccessoryKeyHandler {
        private let client = HayClient()
        private weak var view: HopTermView?
        private let wsBase: String
        private let httpBase: String
        private let token: String?
        private var token_: String? { token }
        private let urlSession: URLSession
        private let room: String
        private let setStatus: (TerminalHostView.ConnState) -> Void
        private let onToast: (String) -> Void
        private var ctrlArmed = false
        private var altArmed = false
        private var lastReconnectToken = 0
        private var retryAttempt = 0
        private var retryTask: Task<Void, Never>?
        private var alive = true

        init(wsBase: String, httpBase: String, token: String?, urlSession: URLSession, room: String,
             onToast: @escaping (String) -> Void,
             setStatus: @escaping (TerminalHostView.ConnState) -> Void) {
            self.onToast = onToast
            self.wsBase = wsBase
            self.httpBase = httpBase
            self.token = token
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
                    self.retryAttempt = 0      // healthy again: reset backoff
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
                case .failed(let reason):
                    self.setStatus(.closed)
                    tv.feed(text: "\r\n\u{1b}[31m[\(reason)]\u{1b}[0m\r\n")
                    self.scheduleRetry()
                case .closed:
                    self.setStatus(.closed)
                    tv.feed(text: "\r\n\u{1b}[2m[disconnected]\u{1b}[0m\r\n")
                    self.scheduleRetry()
                }
            }
            NotificationCenter.default.addObserver(self, selector: #selector(copyScreen),
                                                   name: .hopCopyScreen, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(copyAll),
                                                   name: .hopCopyAll, object: nil)
            let t = view.getTerminal()
            client.connect(base: wsBase, httpBase: httpBase, room: room, cols: t.cols, rows: t.rows,
                           token: token, using: urlSession)
        }

        func detach() {
            alive = false
            retryTask?.cancel()
            NotificationCenter.default.removeObserver(self)
            client.close()
        }

        /// Reconnect on our own with backoff (1s, 2s, 4s, 8s, capped at 15s)
        /// so a tunnel blip or a phone waking from sleep heals itself.
        private func scheduleRetry() {
            guard alive, retryTask == nil else { return }
            let delay = min(15.0, pow(2.0, Double(retryAttempt)))
            retryAttempt += 1
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.alive, !Task.isCancelled else { return }
                await MainActor.run {
                    self.retryTask = nil
                    guard let tv = self.view else { return }
                    self.setStatus(.connecting)
                    let term = tv.getTerminal()
                    self.client.connect(base: self.wsBase, httpBase: self.httpBase, room: self.room,
                                        cols: term.cols, rows: term.rows,
                                        token: self.token_, using: self.urlSession)
                }
            }
        }

        func reconnectIfNeeded(token: Int, view: HopTermView) {
            guard token != lastReconnectToken else { return }
            lastReconnectToken = token
            retryTask?.cancel()
            retryTask = nil
            retryAttempt = 0
            client.close()
            setStatus(.connecting)
            let t = view.getTerminal()
            client.connect(base: wsBase, httpBase: httpBase, room: room,
                           cols: t.cols, rows: t.rows, token: token_, using: urlSession)
        }

        @objc func copyScreen() {
            guard let tv = view else { return }
            let t = tv.getTerminal()
            var lines: [String] = []
            for row in 0..<t.rows {
                if let line = t.getLine(row: row + t.buffer.yDisp) {
                    lines.append(line.translateToString(trimRight: true))
                }
            }
            UIPasteboard.general.string = lines.joined(separator: "\n")
            onToast("Screen copied")
        }

        @objc func copyAll() {
            guard let tv = view else { return }
            let data = tv.getTerminal().getBufferAsData()
            UIPasteboard.general.string = String(data: data, encoding: .utf8) ?? ""
            onToast("Scrollback copied")
        }

        // ── AccessoryKeyHandler ──
        func accessoryKey(_ key: AccessoryKey) {
            switch key {
            case .esc: client.sendInput("\u{1b}")
            case .tab: client.sendInput("\t")
            case .ctrl:
                ctrlArmed.toggle()
                view?.setCtrlArmed(ctrlArmed)
            case .alt:
                altArmed.toggle()
                view?.setAltArmed(altArmed)
            case .ctrlC: client.sendInput("\u{03}")
            case .pipe: client.sendInput("|")
            case .slash: client.sendInput("/")
            case .dash: client.sendInput("-")
            case .tilde: client.sendInput("~")
            case .pageUp: client.sendInput("\u{1b}[5~")
            case .pageDown: client.sendInput("\u{1b}[6~")
            case .up: client.sendInput("\u{1b}[A")
            case .down: client.sendInput("\u{1b}[B")
            case .left: client.sendInput("\u{1b}[D")
            case .right: client.sendInput("\u{1b}[C")
            case .paste:
                if let s = UIPasteboard.general.string { client.sendInput(s) }
            case .dismiss:
                view?.resignFirstResponder()
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
            if altArmed, text.count == 1 {
                text = "\u{1b}" + text          // meta = ESC prefix
                altArmed = false
                view?.setAltArmed(false)
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
enum AccessoryKey {
    case esc, tab, ctrl, alt, ctrlC, up, down, left, right
    case pipe, slash, dash, tilde, pageUp, pageDown, paste, dismiss
}
protocol AccessoryKeyHandler: AnyObject { func accessoryKey(_ key: AccessoryKey) }

final class HopTermView: TerminalView {
    weak var keyHandler: AccessoryKeyHandler?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?

    func applyTheme(light: Bool) {
        if light {
            nativeForegroundColor = UIColor(white: 0.12, alpha: 1)
            nativeBackgroundColor = .white
            backgroundColor = .white
        } else {
            nativeForegroundColor = UIColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1)
            nativeBackgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
            backgroundColor = .black
        }
    }

    /// Scroll to the most recent line containing `needle` (find-in-scrollback).
    func scrollToMatch(_ needle: String) {
        let t = getTerminal()
        let q = needle.lowercased()
        // Search backwards from the bottom of the scrollback; getLine returns
        // nil past the end, which bounds the walk without touching internals.
        var row = t.buffer.yDisp + t.rows
        var probed = 0
        while row > 0 && probed < 5000 {
            row -= 1
            probed += 1
            guard let line = t.getLine(row: row) else { continue }
            if line.translateToString(trimRight: true).lowercased().contains(q) {
                scrollTo(row: max(0, row - t.rows / 2))
                return
            }
        }
    }

    func setAltArmed(_ armed: Bool) {
        altButton?.configuration?.baseForegroundColor = armed ? .black : .white
        altButton?.configuration?.background.backgroundColor =
            armed ? UIColor(red: 0.65, green: 0.55, blue: 0.98, alpha: 1) : UIColor(white: 0.22, alpha: 1)
    }

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
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 46))
        bar.backgroundColor = UIColor(white: 0.11, alpha: 1)

        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(scroller)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(stack)

        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            scroller.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            scroller.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            scroller.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor)
        ])

        // Width per key so labels never wrap ("es/c" was the old failure).
        let keys: [(String, AccessoryKey, CGFloat)] = [
            ("esc", .esc, 50), ("tab", .tab, 50), ("ctrl", .ctrl, 52), ("alt", .alt, 48),
            ("^C", .ctrlC, 46), ("←", .left, 42), ("↓", .down, 42), ("↑", .up, 42), ("→", .right, 42),
            ("|", .pipe, 38), ("/", .slash, 38), ("-", .dash, 38), ("~", .tilde, 38),
            ("⇞", .pageUp, 42), ("⇟", .pageDown, 42), ("paste", .paste, 58), ("⌄", .dismiss, 42)
        ]
        for (label, key, width) in keys {
            var cfg = UIButton.Configuration.filled()
            cfg.title = label
            cfg.baseForegroundColor = .white
            cfg.background.backgroundColor = UIColor(white: 0.22, alpha: 1)
            cfg.background.cornerRadius = 9
            cfg.contentInsets = .zero
            cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
                return out
            }
            let btn = UIButton(configuration: cfg, primaryAction: UIAction { [weak self] _ in
                self?.keyHandler?.accessoryKey(key)
            })
            btn.titleLabel?.lineBreakMode = .byClipping
            btn.titleLabel?.numberOfLines = 1
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: width).isActive = true
            if key == .ctrl { ctrlButton = btn }
            if key == .alt { altButton = btn }
            stack.addArrangedSubview(btn)
        }
        return bar
    }
}
