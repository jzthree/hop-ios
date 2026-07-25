import SwiftUI
import SwiftTerm
import os

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
    @State private var findSeq = 0
    @State private var findDirection = -1
    @State private var findMisses = 0

    /// A find is a REQUEST, identified by a sequence number: the terminal runs
    /// it once. Typing restarts from the live edge; the arrows step from
    /// wherever the last match landed.
    private var findRequest: FindRequest? {
        guard findOpen, !findText.isEmpty else { return nil }
        return FindRequest(query: findText, seq: findSeq, direction: findDirection)
    }
    @State private var findOpen = false
    @State private var reconnectToken = 0
    @State private var controlAction: ControlAction?
    @State private var toast: String?
    @State private var viewers: [HayClient.Viewer] = []
    @State private var collabEveryone = true
    @State private var iHoldControl = false
    @State private var lockedByOther = false
    @State private var scrolledUp = false
    @State private var links: [String] = []
    @State private var showLinks = false
    @Environment(\.scenePhase) private var scenePhase
    enum ConnState { case connecting, live, closed }

    /// Action-sheet labels truncate in the middle by default, which eats the
    /// path — the part that tells two PR links apart. Keep host + tail.
    private func displayLink(_ link: String) -> String {
        let bare = link.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return bare.count <= 48 ? bare : String(bare.prefix(24)) + "…" + String(bare.suffix(20))
    }

    private func setFont(_ size: Double) {
        fontSize = min(24, max(8, size))
        UserDefaults.standard.set(fontSize, forKey: "termFontSize")
    }

    /// Split out of `body` for the same reason SessionsView is: the whole
    /// chain in one expression blows the SwiftUI type-checker's budget.
    private var screen: some View {
        TerminalScreen(model: model, room: session.internalName, status: $status,
                       fontSize: fontSize, lightTheme: lightTheme,
                       find: findRequest, reconnectToken: reconnectToken,
                       onToast: { toast = $0 },
                       onLinks: { found in
                           links = found
                           if found.isEmpty { toast = "No links on screen" } else { showLinks = true }
                       },
                       onFontChange: { setFont($0) },
                       onPresence: { viewers = $0 },
                       onCollab: { everyone, mine, other in
                           collabEveryone = everyone; iHoldControl = mine; lockedByOther = other
                       },
                       control: $controlAction,
                       onScroll: { scrolledUp = $0 })
    }

    var body: some View {
        screen
            .padding(.horizontal, 5)
            .ignoresSafeArea(.container, edges: .bottom)
            .confirmationDialog("Links on screen", isPresented: $showLinks, titleVisibility: .visible) {
                // Newest first, and capped: a build log can put dozens on
                // screen and an endless action sheet is unusable.
                ForEach(links.prefix(8), id: \.self) { link in
                    Button(displayLink(link)) {
                        if let url = URL(string: link) { UIApplication.shared.open(url) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .overlay(alignment: .bottomTrailing) {
                if scrolledUp {
                    Button {
                        NotificationCenter.default.post(name: .hopJumpToLive, object: nil)
                    } label: {
                        Label("Live", systemImage: "arrow.down.to.line")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.hopPurple, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
            }
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
                            .onChange(of: findText) { _, _ in
                                findDirection = -1      // new query: newest match first
                                findMisses = 0
                                findSeq += 1
                            }
                        Button {
                            findDirection = -1          // older
                            findSeq += 1
                        } label: { Image(systemName: "chevron.up") }
                            .accessibilityLabel("Previous match")
                        Button {
                            findDirection = 1           // newer
                            findSeq += 1
                        } label: { Image(systemName: "chevron.down") }
                            .accessibilityLabel("Next match")
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
                    Menu {
                        Section("Switch session") {
                            ForEach(model.sessions.filter {
                                $0.internalName != session.internalName && $0.live && !$0.isPort
                            }.prefix(12)) { other in
                                Button {
                                    model.requestedSession = other.internalName
                                } label: {
                                    Label(other.attention ? "\(other.name) ●" : other.name,
                                          systemImage: other.createdBy == "agent" ? "cpu" : "terminal")
                                }
                            }
                        }
                    } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(status == .live ? Color.green : status == .connecting ? Color.yellow : Color.red)
                            .frame(width: 8, height: 8)
                        Text(session.name)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        if lockedByOther {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
                        } else if !collabEveryone && iHoldControl {
                            Image(systemName: "hand.raised.fill").font(.caption2).foregroundStyle(Color.hopGlow)
                        }
                        if viewers.count > 1 {
                            Label("\(viewers.count)", systemImage: "person.2.fill")
                                .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                        }
                        if !session.runningApp.isEmpty {
                            Text(session.runningApp)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.hopPurple.opacity(0.22), in: Capsule())
                                .foregroundStyle(Color.hopGlow)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    }
                    .tint(.primary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { controlAction = .links } label: {
                            Label("Open link…", systemImage: "link")
                        }
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
                        // Who else is here + who may type (hay collab model).
                        if !viewers.isEmpty {
                            Section("Viewers") {
                                ForEach(viewers) { v in
                                    Label(v.typing ? "\(v.name) — typing" : v.name,
                                          systemImage: "person.fill")
                                }
                            }
                        }
                        Button {
                            controlAction = collabEveryone ? .lock : .unlock
                        } label: {
                            Label(collabEveryone ? "Lock typing to one user" : "Let everyone type",
                                  systemImage: collabEveryone ? "lock" : "lock.open")
                        }
                        if !collabEveryone {
                            Button {
                                controlAction = iHoldControl ? .release : .take
                            } label: {
                                Label(iHoldControl ? "Release control" : "Take control",
                                      systemImage: iHoldControl ? "hand.raised.slash" : "hand.raised")
                            }
                        }
                        Divider()
                        Button { reconnectToken += 1 } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Terminal actions")
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // iOS suspends the socket when the app backgrounds; coming back
                // to a dead terminal and having to hunt for a menu item was the
                // single most annoying part of using this on a phone.
                // Only a CLOSED socket needs this. Firing on .connecting too
                // meant becoming active while the first connect was still in
                // flight tore it down and started over — and every connect
                // pulls a fresh snapshot, up to 1.5 MB, on someone's cellular.
                if phase == .active, status == .closed { reconnectToken += 1 }
            }
            .onAppear {
                model.openSession = session.internalName
                model.markSeen(session)
            }
            .onDisappear {
                // Guard the identity: switching sessions can appear-then-
                // disappear, and a blind clear would wipe the new one.
                if model.openSession == session.internalName { model.openSession = nil }
            }
            .background(Color.black)
    }
}

/// One find, identified by `seq` so the terminal runs it exactly once.
struct FindRequest: Equatable {
    let query: String
    let seq: Int
    let direction: Int
}

enum ControlAction { case take, release, lock, unlock, links }

extension Notification.Name {
    static let hopCopyScreen = Notification.Name("hopCopyScreen")
    static let hopCopyAll = Notification.Name("hopCopyAll")
    static let hopJumpToLive = Notification.Name("hopJumpToLive")
}

struct TerminalScreen: UIViewRepresentable {
    let model: AppModel
    let room: String
    @Binding var status: TerminalHostView.ConnState
    var fontSize: Double = 12
    var lightTheme = false
    var find: FindRequest?
    var reconnectToken = 0
    var onToast: (String) -> Void = { _ in }
    var onLinks: ([String]) -> Void = { _ in }
    var onFontChange: (Double) -> Void = { _ in }
    var onPresence: ([HayClient.Viewer]) -> Void = { _ in }
    var onCollab: (Bool, Bool, Bool) -> Void = { _, _, _ in }
    @Binding var control: ControlAction?
    var onScroll: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(wsBase: model.wsBase, httpBase: model.normalizedServerURL, token: model.accessToken,
                    urlSession: model.urlSession, room: room, onToast: onToast, onLinks: onLinks,
                    onFontChange: onFontChange,
                    onPresence: onPresence, onCollab: onCollab, onScroll: onScroll) { status = $0 }
    }

    func makeUIView(context: Context) -> HopTermView {
        let tv = HopTermView(frame: .zero)
        tv.terminalDelegate = context.coordinator
        tv.keyHandler = context.coordinator
        tv.installAccessoryBar()
        tv.backgroundColor = .black
        tv.nativeForegroundColor = UIColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1)
        tv.nativeBackgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        tv.addGestureRecognizer(pinch)
        context.coordinator.attach(view: tv)
        tv.becomeFirstResponder()
        return tv
    }

    func updateUIView(_ uiView: HopTermView, context: Context) {
        uiView.font = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        uiView.applyTheme(light: lightTheme)
        // Only on a new request. Re-running whenever anything else updated
        // meant the list's background refresh yanked the view back to the
        // match every few seconds while you were trying to read around it.
        if let find { context.coordinator.runFind(find, view: uiView) }
        context.coordinator.reconnectIfNeeded(token: reconnectToken, view: uiView)
        if let action = control {
            context.coordinator.apply(action)
            DispatchQueue.main.async { self.control = nil }
        }
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
        private let pushStatus: (TerminalHostView.ConnState) -> Void
        private var isLive = false
        private var lastDeadToast = Date.distantPast

        private var pending = PendingInput()

        /// Every keystroke goes through here: straight out on a live socket,
        /// buffered otherwise. A terminal's echo comes from the SERVER, so
        /// silence during an outage reads as a frozen app — hence the toast,
        /// throttled, since a burst of typing would be a burst of toasts.
        private func deliver(_ text: String) {
            guard !text.isEmpty else { return }
            if isLive {
                client.sendInput(text)
                markTyping()
                return
            }
            pending.append(text, at: Date())
            if Date().timeIntervalSince(lastDeadToast) > 2 {
                lastDeadToast = Date()
                onToast("Reconnecting — input buffered")
            }
        }

        /// Replay on reconnect: in order, as one message, and only what is
        /// still fresh. Stale input is discarded and SAID so — silently
        /// dropping keystrokes someone watched themselves type is worse than
        /// admitting it.
        private func replayPending() {
            guard !pending.isEmpty else { return }
            let (replay, dropped) = pending.drain(now: Date())
            if !replay.isEmpty {
                client.sendInput(replay)
                onToast("Reconnected — buffered input sent")
            }
            if dropped > 0 { onToast("Reconnected — stale buffered input discarded") }
        }

        // Presence: other viewers see "typing" only if we say so. Transitions
        // only, with the web client's 1.2s idle window.
        private var typingActive = false
        private var typingTimer: Timer?

        private func markTyping() {
            if !typingActive {
                typingActive = true
                client.sendTyping(true)
            }
            typingTimer?.invalidate()
            typingTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.typingActive = false
                self.client.sendTyping(false)
            }
        }

        private func setStatus(_ state: TerminalHostView.ConnState) {
            isLive = state == .live
            pushStatus(state)
        }
        private let onToast: (String) -> Void
        private let onLinks: ([String]) -> Void
        private let onFontChange: (Double) -> Void
        private let onPresence: ([HayClient.Viewer]) -> Void
        private let onCollab: (Bool, Bool, Bool) -> Void
        private let onScroll: (Bool) -> Void
        private var ctrlArmed = false
        private var altArmed = false
        private var lastReconnectToken = 0
        private var retryAttempt = 0
        private var retryTask: Task<Void, Never>?
        private var alive = true

        init(wsBase: String, httpBase: String, token: String?, urlSession: URLSession, room: String,
             onToast: @escaping (String) -> Void,
             onLinks: @escaping ([String]) -> Void,
             onFontChange: @escaping (Double) -> Void,
             onPresence: @escaping ([HayClient.Viewer]) -> Void,
             onCollab: @escaping (Bool, Bool, Bool) -> Void,
             onScroll: @escaping (Bool) -> Void,
             setStatus: @escaping (TerminalHostView.ConnState) -> Void) {
            self.onScroll = onScroll
            self.onToast = onToast
            self.onLinks = onLinks
            self.onFontChange = onFontChange
            self.onPresence = onPresence
            self.onCollab = onCollab
            self.wsBase = wsBase
            self.httpBase = httpBase
            self.token = token
            self.urlSession = urlSession
            self.room = room
            self.pushStatus = setStatus
        }

        func attach(view: HopTermView) {
            self.view = view
            client.onEvent = { [weak self] event in
                guard let self, let tv = self.view else { return }
                switch event {
                case .connected:
                    self.retryAttempt = 0      // healthy again: reset backoff
                    self.setStatus(.live)
                    self.claimSizeOnAttach()
                    self.replayPending()
                case .output(let data):
                    tv.feed(text: data)
                case .presence(let list):
                    self.onPresence(list)
                case .collab(let everyone, let controllerId):
                    let mine = controllerId != nil && controllerId == self.client.clientId
                    self.onCollab(everyone, mine, !everyone && !mine && controllerId != nil)
                case .rejected(let reason):
                    self.onToast(reason)
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
            NotificationCenter.default.addObserver(self, selector: #selector(jumpToLive),
                                                   name: .hopJumpToLive, object: nil)
            let t = view.getTerminal()
            client.connect(base: wsBase, httpBase: httpBase, room: room, cols: t.cols, rows: t.rows,
                           token: token, using: urlSession)
        }

        /// Pinch the terminal to size the text, like every other iOS reader.
        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let tv = view, g.state == .changed, abs(g.scale - 1) > 0.15 else { return }
            let current = tv.font.pointSize
            let next = min(24, max(8, current + (g.scale > 1 ? 1 : -1)))
            g.scale = 1
            guard next != current else { return }
            // Report it UP rather than setting the font here. updateUIView
            // rewrites the font from SwiftUI's fontSize on every update, so a
            // local-only change was silently reverted by the next toast,
            // presence change or list refresh — pinch appeared to work and
            // then snapped back, with the new size only showing up the next
            // time the terminal was opened.
            onFontChange(Double(next))
        }

        func apply(_ action: ControlAction) {
            switch action {
            case .take: client.takeControl()
            case .release: client.releaseControl()
            case .lock: client.setCollab(false)
            case .unlock: client.setCollab(true)
            case .links: onLinks(visibleLinks())
            }
        }

        private var lastFindSeq = 0
        private var lastFindQuery = ""
        private var findCursor: Int?

        /// A new query starts at the live edge and walks back — the newest
        /// match is nearly always the one you want. The arrows continue from
        /// the last match, which is what makes hunting an EARLIER occurrence
        /// possible at all; before this, every search returned the same row.
        func runFind(_ request: FindRequest, view: HopTermView) {
            guard request.seq != lastFindSeq else { return }
            lastFindSeq = request.seq
            let restarted = request.query != lastFindQuery
            lastFindQuery = request.query
            if restarted { findCursor = nil }
            let start = findCursor ?? view.liveEdgeRow
            if let row = view.scrollToMatch(request.query, from: start, direction: request.direction) {
                findCursor = row
            } else if !restarted {
                // Ran off the end rather than "no such text": say which.
                onToast(request.direction < 0 ? "No earlier match" : "No later match")
            } else {
                onToast("Not found")
            }
        }

        /// Links on the visible screen. Wrapped rows are rejoined first — a
        /// long URL arrives as two rows with no newline between them.
        /// SwiftTerm keeps BufferLine.isWrapped internal, so infer it the way
        /// terminals themselves do: a row that filled its last column ran on.
        private func visibleLinks() -> [String] {
            guard let t = view?.getTerminal() else { return [] }
            var rows: [(text: String, wrapped: Bool)] = []
            var previousFilledLastColumn = false
            for row in 0..<t.rows {
                guard let line = t.getLine(row: row + t.buffer.yDisp) else { continue }
                let full = line.translateToString(trimRight: false)
                rows.append((line.translateToString(trimRight: true), previousFilledLastColumn))
                previousFilledLastColumn = full.count >= t.cols
                    && !(full.last?.isWhitespace ?? true)
            }
            return extractLinks(from: screenText(rows: rows))
        }

        func detach() {
            alive = false
            typingTimer?.invalidate()
            if typingActive { client.sendTyping(false) }
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

        @objc func jumpToLive() {
            guard let tv = view else { return }
            // Scroll past the end; SwiftTerm clamps to the live edge.
            tv.scrollTo(row: Int.max / 2)
            onScroll(false)
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
        func accessoryKey(_ key: AccessoryKey, isRepeat: Bool) {
            switch key {
            case .ctrl:
                ctrlArmed.toggle()
                view?.setCtrlArmed(ctrlArmed)
            case .alt:
                altArmed.toggle()
                view?.setAltArmed(altArmed)
            case .dismiss:
                view?.resignFirstResponder()
            default:
                if let seq = key.sequence { deliver(seq) }
            }
            // Only the press buzzes. A held key repeats ~18x a second, and
            // haptics on every tick is a drill, not feedback.
            if !isRepeat { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
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
            deliver(text)
        }

        /// The size this phone's view actually fits, recorded from layout —
        /// NOT read back off the terminal, which a peer's active_size may have
        /// already widened to a desktop's dimensions by the time we connect.
        private var fittedCols = 0
        private var fittedRows = 0

        private func claimSizeOnAttach() {
            let t = view?.getTerminal()
            let cols = fittedCols > 0 ? fittedCols : (t?.cols ?? 0)
            let rows = fittedRows > 0 ? fittedRows : (t?.rows ?? 0)
            guard cols > 0, rows > 0 else { return }
            client.sendResize(cols: cols, rows: rows, claim: "attach")
            Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                .info("attach claim \(cols)x\(rows) for \(self.room, privacy: .public)")
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            fittedCols = newCols
            fittedRows = newRows
            client.sendResize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {
            // >0.999 means pinned to the live edge; anything less is history.
            onScroll(position < 0.999)
        }
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

    /// What this key puts on the wire; nil for keys that only arm a modifier
    /// or dismiss the keyboard. Data rather than a switch full of send calls,
    /// so the escape sequences are testable.
    var sequence: String? {
        switch self {
        case .esc: return "\u{1b}"
        case .tab: return "\t"
        case .ctrlC: return "\u{03}"
        case .pipe: return "|"
        case .slash: return "/"
        case .dash: return "-"
        case .tilde: return "~"
        case .pageUp: return "\u{1b}[5~"
        case .pageDown: return "\u{1b}[6~"
        case .up: return "\u{1b}[A"
        case .down: return "\u{1b}[B"
        case .left: return "\u{1b}[D"
        case .right: return "\u{1b}[C"
        case .paste: return UIPasteboard.general.string
        case .ctrl, .alt, .dismiss: return nil
        }
    }

    /// Keys that put bytes on the wire, as opposed to arming a modifier or
    /// dismissing the keyboard. (`paste` counts even when the pasteboard is
    /// empty — it is an input key that happened to have nothing to say.)
    var sendsInput: Bool {
        switch self {
        case .ctrl, .alt, .dismiss: return false
        default: return true
        }
    }

    /// Keys that repeat while held, like a real keyboard. Navigation only:
    /// a stuck ^C or a repeating paste is destructive, and repeating a
    /// modifier would just flap its armed state.
    var repeats: Bool {
        switch self {
        case .up, .down, .left, .right, .pageUp, .pageDown: return true
        default: return false
        }
    }
}
protocol AccessoryKeyHandler: AnyObject {
    func accessoryKey(_ key: AccessoryKey, isRepeat: Bool)
}
extension AccessoryKeyHandler {
    func accessoryKey(_ key: AccessoryKey) { accessoryKey(key, isRepeat: false) }
}

final class HopTermView: TerminalView {
    weak var keyHandler: AccessoryKeyHandler?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var repeatTimer: Timer?

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
    /// Finds the next match from `start` and scrolls it into view, returning
    /// the row it landed on so the caller can continue from there.
    func scrollToMatch(_ needle: String, from start: Int, direction: Int) -> Int? {
        let t = getTerminal()
        guard let row = findMatchRow(from: start, direction: direction, needle: needle, line: { r in
            t.getLine(row: r)?.translateToString(trimRight: true)
        }) else { return nil }
        scrollTo(row: max(0, row - t.rows / 2))
        return row
    }

    var liveEdgeRow: Int { getTerminal().buffer.yDisp + getTerminal().rows }

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

    // MARK: hold-to-repeat

    private var repeatKeys: [ObjectIdentifier: AccessoryKey] = [:]

    @objc private func beginRepeat(_ sender: UIButton) {
        guard let key = repeatKeys[ObjectIdentifier(sender)] else { return }
        endRepeat()
        keyHandler?.accessoryKey(key)               // instant first keystroke
        // Then iOS keyboard cadence, a little quicker — a terminal's ↓ is
        // held to walk history, not to type a character.
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] _ in
                self?.keyHandler?.accessoryKey(key, isRepeat: true)
            }
        }
    }

    /// A scheduled Timer is owned by the run loop, and capturing self weakly
    /// only makes its ticks harmless — it still fires every 55ms forever. Leave
    /// the screen mid-hold (session ends, interactive back gesture) and nothing
    /// on the touch path ever stops it.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { endRepeat() }
    }

    deinit { repeatTimer?.invalidate() }

    @objc private func endRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
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
        // Third element is the spoken name: "⇞" and "⌄" are unreadable to
        // VoiceOver and unsayable to Voice Control ("tap page up" should work).
        let keys: [(String, AccessoryKey, CGFloat, String)] = [
            ("esc", .esc, 50, "escape"), ("tab", .tab, 50, "tab"),
            ("ctrl", .ctrl, 52, "control"), ("alt", .alt, 48, "alt"),
            ("^C", .ctrlC, 46, "control C"),
            ("←", .left, 42, "left arrow"), ("↓", .down, 42, "down arrow"),
            ("↑", .up, 42, "up arrow"), ("→", .right, 42, "right arrow"),
            ("|", .pipe, 38, "pipe"), ("/", .slash, 38, "slash"),
            ("-", .dash, 38, "dash"), ("~", .tilde, 38, "tilde"),
            ("⇞", .pageUp, 42, "page up"), ("⇟", .pageDown, 42, "page down"),
            ("paste", .paste, 58, "paste"), ("⌄", .dismiss, 42, "hide keyboard")
        ]
        for (label, key, width, spoken) in keys {
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
            // Repeating keys fire on touch-DOWN and drive themselves after
            // that, so the first keystroke is instant. Everything else keeps
            // the standard touch-up action (a tap you can slide off to cancel).
            let action = key.repeats ? nil : UIAction { [weak self] _ in
                self?.keyHandler?.accessoryKey(key)
            }
            let btn = UIButton(configuration: cfg, primaryAction: action)
            if key.repeats {
                repeatKeys[ObjectIdentifier(btn)] = key
                btn.addTarget(self, action: #selector(beginRepeat(_:)), for: .touchDown)
                for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
                    btn.addTarget(self, action: #selector(endRepeat), for: event)
                }
            }
            btn.accessibilityLabel = spoken
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
