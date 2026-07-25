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
    /// Renaming happens on the desktop too; without this the title here stays
    /// wrong until the next list refresh.
    @State private var renamedTitle: String?
    /// Height of the key bar while the keyboard is up. SwiftUI's keyboard
    /// avoidance insets for the keyboard but NOT for an inputAccessoryView, so
    /// the terminal's frame ran on underneath the strip and autofit sized rows
    /// for space the user cannot see — the bottom of the session, including
    /// claude's prompt line, sat behind the keys.
    @State private var accessoryInset: CGFloat = 0
    /// Set when the session is gone for good — ended, or a room the server no
    /// longer has. A red line buried in the scrollback is easy to miss when
    /// you've just tapped in expecting a live terminal.
    @State private var goneReason: String? = {
#if DEBUG
        ProcessInfo.processInfo.environment["HOP_DEV_GONE"] == "1" ? "Session terminated" : nil
#else
        nil
#endif
    }()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.dismiss) private var dismiss

    /// Landscape on a phone: the keyboard eats over half the height, so every
    /// point of chrome costs a line of terminal. Hide the nav bar and status
    /// bar and give the rest to the session. HOP_DEV_COMPACT=1 forces it in
    /// portrait, because the simulator can't be rotated from a script.
    private var landscapePhone: Bool {
        verticalSize == .compact || ProcessInfo.processInfo.environment["HOP_DEV_COMPACT"] == "1"
    }
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
                       onRenamed: { renamedTitle = $0 },
                       onGone: { goneReason = $0 },
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
            .padding(.bottom, accessoryInset)
            // Deliberately NOT ignoring the bottom safe area. Doing so let the
            // terminal run under the home indicator with the keyboard down, and
            // autofit counted those rows too — the same defect as the key bar,
            // a different strip. Last lines behind a system control is worse
            // than a 34pt margin.
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                // The keyboard's own height is already handled; what's missing
                // is the accessory riding on top of it. Zero when the keyboard
                // is down, since the bar goes with it.
                guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                      let screen = UIApplication.shared.connectedScenes
                          .compactMap({ ($0 as? UIWindowScene)?.screen.bounds.height }).first
                else { return }
                let up = end.origin.y < screen
                accessoryInset = up ? HopTermView.accessoryHeight : 0
            }
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
            .overlay {
                if let goneReason {
                    VStack(spacing: 12) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 28)).foregroundStyle(.secondary)
                        Text("Session ended").font(.headline)
                        Text(goneReason)
                            .font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Back to sessions") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(.hopPurple)
                    }
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(32)
                    // The scrollback stays readable behind it — the last thing
                    // the session printed is usually why you opened it.
                    .transition(.opacity)
                }
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
                    .background(Color.hopRaised)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(landscapePhone ? .hidden : .visible, for: .navigationBar)
            .statusBarHidden(landscapePhone)
            .toolbarBackground(Color.hopRaised, for: .navigationBar)
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
                        Text(renamedTitle ?? session.name)
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
            .background(Color.hopSurface)
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
    var onRenamed: (String) -> Void = { _ in }
    var onGone: (String) -> Void = { _ in }
    var onPresence: ([HayClient.Viewer]) -> Void = { _ in }
    var onCollab: (Bool, Bool, Bool) -> Void = { _, _, _ in }
    @Binding var control: ControlAction?
    var onScroll: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(wsBase: model.wsBase, httpBase: model.normalizedServerURL, token: model.accessToken,
                    urlSession: model.urlSession, room: room, onToast: onToast, onLinks: onLinks,
                    onFontChange: onFontChange, onRenamed: onRenamed, onGone: onGone,
                    onPresence: onPresence, onCollab: onCollab, onScroll: onScroll) { status = $0 }
    }

    func makeUIView(context: Context) -> HopTermView {
        let tv = HopTermView(frame: .zero)
        tv.installScrollGesture()
        // A blinking caret is a permanent animation, and XCUITest waits for
        // animations to finish before every interaction — so each tap sat
        // through a 60s "app never became idle" timeout, making the suite take
        // longer than a coffee break and hiding real failures behind noise.
        // Steady cursor under test only; the app keeps its blink.
        if ProcessInfo.processInfo.arguments.contains("-hop-ui-testing") {
            tv.getTerminal().setCursorStyle(.steadyBlock)
        }
        // SwiftTerm keeps 500 lines by default, but hop's join snapshot is a
        // full client scrollback — up to 1.5 MB. We were downloading tens of
        // thousands of lines and discarding all but the last 500, so "copy all
        // scrollback" and find-in-scrollback couldn't reach what we'd already
        // paid to fetch. 5000 matches the find walk's own limit.
        tv.getTerminal().changeScrollback(5000)
        tv.terminalDelegate = context.coordinator
        tv.keyHandler = context.coordinator
        tv.installAccessoryBar()
        tv.backgroundColor = .black
        tv.nativeForegroundColor = UIColor(red: 0.90, green: 0.90, blue: 0.91, alpha: 1)
        tv.nativeBackgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        tv.addGestureRecognizer(pinch)
        context.coordinator.themeIsLight = lightTheme
        context.coordinator.attach(view: tv)
        _ = tv.becomeFirstResponder()
        return tv
    }

    func updateUIView(_ uiView: HopTermView, context: Context) {
        uiView.font = UIFont.monospacedSystemFont(ofSize: CGFloat(fontSize), weight: .regular)
        uiView.applyTheme(light: lightTheme)
        context.coordinator.themeIsLight = lightTheme
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
        private let onRenamed: (String) -> Void
        private let onGone: (String) -> Void
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
             onRenamed: @escaping (String) -> Void,
             onGone: @escaping (String) -> Void,
             onPresence: @escaping ([HayClient.Viewer]) -> Void,
             onCollab: @escaping (Bool, Bool, Bool) -> Void,
             onScroll: @escaping (Bool) -> Void,
             setStatus: @escaping (TerminalHostView.ConnState) -> Void) {
            self.onScroll = onScroll
            self.onToast = onToast
            self.onLinks = onLinks
            self.onFontChange = onFontChange
            self.onRenamed = onRenamed
            self.onGone = onGone
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
                    // How much history the snapshot actually delivered. This is
                    // the number that decides whether find and copy-all can
                    // reach anything, so it's worth being able to look it up
                    // rather than assume.
                    // @MainActor, not a bare Task: SwiftTerm's Terminal is
                    // main-actor-isolated and its buffer is plain arrays, so
                    // walking it off the main thread races the feed writing
                    // into it. Strict-concurrency checking caught this; it was
                    // a diagnostic log quietly reading a live data structure
                    // from the wrong thread.
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(3))
                        guard let self, let t = self.view?.getTerminal() else { return }
                        // yBase is internal in SwiftTerm, so count what the
                        // public accessor will actually return — which is the
                        // number that matters anyway, since find and copy-all
                        // go through the same door.
                        var depth = 0
                        while depth < 6000, t.getLine(row: depth) != nil { depth += 1 }
                        Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                            .info("scrollback reachable \(depth) lines, altScreen=\(self.lastAltScreen)")
                    }
                case .output(let data):
                    tv.noteRemoteModes(in: data)
                    tv.feed(text: data)
                case .snapshot(let data, let alternateScreen, let cursorHidden,
                               let mouseReporting, let mouseSgr):
                    self.snapshotLanded = true
                    self.lastAltScreen = alternateScreen
                    // A snapshot is the whole session replayed, so it has to
                    // land on a clean terminal. Feeding it into the existing
                    // one duplicated history for shell sessions and let stale
                    // state bleed across the reconnect — cursor column, SGR
                    // attributes, alt-screen and mouse-reporting modes. hop's
                    // web client resets for exactly this reason; the symptom it
                    // records is mouse reports arriving as junk input
                    // ("35;197;31M") at a prompt that never asked for them.
                    // This path runs on EVERY return from background.
                    tv.getTerminal().resetToInitialState()
                    // Re-enter the modes the app is actually in. SwiftTerm keeps
                    // the buffer switch private, but a terminal takes modes as
                    // sequences, which is the honest way to say it anyway.
                    // Mouse reporting is deliberately NOT restored: on a touch
                    // screen a tap is how you reach the keyboard, and turning
                    // taps into clicks at the app is a behaviour change worth
                    // deciding on a device, not guessing at here.
                    if alternateScreen { tv.feed(text: "\u{1b}[?1049h") }
                    if cursorHidden { tv.feed(text: "\u{1b}[?25l") }
                    // Mouse reporting is NOT fed into the terminal — it is
                    // recorded beside it. The scroll code needs to know whether
                    // the REMOTE app takes wheel events, and feeding ?1000h
                    // would answer that by changing what our own terminal does,
                    // which is a side effect to buy a fact. hop's web client
                    // keeps the same two flags in refs for the same reason, and
                    // it needs SGR specifically: without it the app expects the
                    // legacy encoding, which caps coordinates at 223.
                    tv.setRemoteMouse(reporting: mouseReporting, sgr: mouseSgr)
                    tv.feed(text: data)
                case .presence(let list):
                    self.onPresence(list)
                case .collab(let everyone, let controllerId):
                    let mine = controllerId != nil && controllerId == self.client.clientId
                    self.onCollab(everyone, mine, !everyone && !mine && controllerId != nil)
                case .rejected(let reason):
                    self.onToast(reason)
                case .joined(let cols, let rows):
                    self.sizeAtJoin = (cols, rows)
                case .renamed(let name):
                    self.onRenamed(name)
                case .serverError(let message):
                    self.onToast(message)
                    Logger(subsystem: "io.zhoulab.hop.spike", category: "protocol")
                        .error("server rejected a message: \(message, privacy: .public)")
                case .activeSize(let cols, let rows):
                    if tv.getTerminal().cols != cols || tv.getTerminal().rows != rows {
                        tv.getTerminal().resize(cols: cols, rows: rows)
                    }
                case .ended(let message):
                    self.setStatus(.closed)
                    self.onGone(message)
                    tv.feed(text: "\r\n\u{1b}[2m[\(message)]\u{1b}[0m\r\n")
                case .failed(let reason, let permanent):
                    self.setStatus(.closed)
                    if permanent { self.onGone(reason) }
                    tv.feed(text: "\r\n\u{1b}[31m[\(reason)]\u{1b}[0m\r\n")
                    // A gone room or a rejected identity won't fix itself.
                    if !permanent { self.scheduleRetry() }
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
            snapshotLanded = false
            claimed = false
            client.theme = themeIsLight ? .light : .dark
            fastPaint(room: room)
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

        /// Set once the authoritative replay lands, so the fast paint below
        /// can never scribble over it if it loses the race.
        private var snapshotLanded = false
        /// The palette this view is rendering, mirrored from SwiftUI state so
        /// the room can be told the background a TUI should theme itself for.
        var themeIsLight = false

        /// Fast first paint. hop can serialize a session's CURRENT screen from
        /// its preview grid in one small response (~2 KB) — paint that at once
        /// so opening a session shows content while the WebSocket snapshot,
        /// measured at 2.4 MB, is still downloading. On a phone over a tunnel
        /// that download IS the wait. The snapshot handler resets the terminal
        /// before writing, so this paint is fully superseded rather than
        /// merged. Best-effort throughout: any failure just means the old
        /// behaviour, a blank terminal until the snapshot arrives.
        private func fastPaint(room: String) {
            guard var comps = URL(string: httpBase)
                .map({ $0.appendingPathComponent("api/sessions/screen") })
                .flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return }
            comps.queryItems = [.init(name: "name", value: room)]
            guard let url = comps.url else { return }
            var req = URLRequest(url: url)
            req.timeoutInterval = 5
            if let t = token_, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
            let session = urlSession
            // @MainActor on the Task rather than a nested MainActor.run: the
            // network await still suspends off-main, the body resumes on the
            // main actor, and `self` is no longer a captured var crossing into
            // concurrent code — which Swift 6 rejects outright.
            Task { @MainActor [weak self] in
                guard let (data, resp) = try? await session.data(for: req),
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let screen = obj["data"] as? String, !screen.isEmpty else { return }
                guard let self, self.alive, !self.snapshotLanded,
                      self.room == room, let tv = self.view else { return }
                // Paint at the session's real dimensions: writing a wide
                    // screen into a narrow grid wraps it into mush.
                let t = tv.getTerminal()
                if let cols = obj["cols"] as? Int, let rows = obj["rows"] as? Int,
                   cols > 1, rows > 1, t.cols != cols || t.rows != rows {
                    t.resize(cols: cols, rows: rows)
                }
                tv.feed(text: screen)
                Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                    .info("fast paint \(screen.utf8.count / 1024) KB (snapshot still in flight)")
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
                    // The automatic retry is the MOST common reconnect — a
                    // tunnel blip, or a phone waking up — and it was the one
                    // path that never fast-painted, so the case where you're
                    // already staring at a dead terminal was the slowest.
                    self.snapshotLanded = false
                    self.claimed = false
                    self.fastPaint(room: self.room)
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
            snapshotLanded = false
            claimed = false
            fastPaint(room: room)
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
                _ = view?.resignFirstResponder()
            case .paste:
                // Through SwiftTerm, not straight down the socket: when the
                // app has bracketed paste on, it wraps the text in
                // ESC[200~ / ESC[201~ so a multi-line paste arrives as ONE
                // paste. Sending it raw meant every newline executed a line —
                // and pasting is exactly what you do on a phone instead of
                // typing. Its send path still lands in deliver(), so buffering
                // while disconnected keeps working.
                view?.paste(nil)
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

        /// What the room was sized to when we arrived, so the claim below can
        /// tell "I fit this to the phone" from "I just reshaped the terminal
        /// someone is using at their desk".
        private var sizeAtJoin: (cols: Int, rows: Int)?
        private(set) var lastAltScreen = false

        /// Resizes are held until this is true. Opening a session used to send
        /// TWO: the claim at the pre-keyboard height, then another when the
        /// keyboard appeared and took half the screen. One PTY means everyone
        /// reflows both times — a desk terminal redrawing twice because someone
        /// glanced at their phone.
        private var claimed = false

        private func claimSizeOnAttach() {
            // Let the keyboard's layout land first, then claim once at the
            // size we'll actually keep.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.sendAttachClaim()
            }
        }

        private func sendAttachClaim() {
            guard !claimed else { return }
            claimed = true
            let t = view?.getTerminal()
            let cols = fittedCols > 0 ? fittedCols : (t?.cols ?? 0)
            let rows = fittedRows > 0 ? fittedRows : (t?.rows ?? 0)
            guard cols > 0, rows > 0 else { return }
            client.sendResize(cols: cols, rows: rows, claim: "attach")
            Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                .info("attach claim \(cols)x\(rows) for \(self.room, privacy: .public)")
            // One PTY means one size, so opening a session here reflows it
            // everywhere — including whatever screen it was sized for. Say so
            // when the change is real, rather than letting a desk terminal
            // reflow for no visible reason. It self-heals: whoever types next
            // takes the size back.
            if let was = sizeAtJoin, was.cols > 0, abs(was.cols - cols) > 8 {
                onToast("Resized to \(cols)×\(rows) for this screen (was \(was.cols)×\(was.rows))")
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            fittedCols = newCols
            fittedRows = newRows
            // Before the claim, record only. Sending now would reshape the PTY
            // at a height the keyboard is about to take away.
            guard claimed else { return }
            Logger(subsystem: "io.zhoulab.hop.spike", category: "layout")
                .info("fit \(newCols)x\(newRows) in \(Int(source.bounds.height))pt view, accessory \(Int(source.inputAccessoryView?.bounds.height ?? 0))pt")
            client.sendResize(cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {
            // >0.999 means pinned to the live edge; anything less is history.
            // But a session with no scrollback at all reports 0, which made the
            // "Live" button sit there permanently on a fresh TUI session —
            // offering to return you to a place you had never left.
            let t = source.getTerminal()
            let hasHistory = t.getLine(row: t.rows) != nil
            onScroll(hasHistory && position < 0.999)
        }
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            // OSC 8 hyperlinks come from session output, which for an agent
            // session is arbitrary command output. Web links only: a `tel:`,
            // `facetime:` or app-scheme URL would turn a tap on what looks
            // like a link into an action nobody asked for.
            guard let u = URL(string: link), let scheme = u.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                onToast("Only web links can be opened")
                return
            }
            UIApplication.shared.open(u)
        }
        func clipboardCopy(source: TerminalView, content: Data) {
            // OSC 52: the session asking to WRITE the clipboard. Honoured,
            // because `yy` in vim or a tmux copy reaching the iOS clipboard is
            // a real workflow — but never silently. On iOS the clipboard is
            // shared with every app and mirrored to the Mac by Universal
            // Clipboard, so an unannounced replacement of what you had copied
            // is the part that's unacceptable, not the write itself.
            // (hop's web client swallows OSC 52, but a browser has little
            // choice: clipboard writes without a user gesture are restricted.)
            guard let text = String(data: content, encoding: .utf8), !text.isEmpty else { return }
            UIPasteboard.general.string = text
            onToast("Clipboard set by session")
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
    case esc, tab, shiftTab, ctrl, alt, ctrlC, up, down, left, right
    case pipe, slash, dash, tilde, pageUp, pageDown, paste, dismiss

    /// What this key puts on the wire; nil for keys that only arm a modifier
    /// or dismiss the keyboard. Data rather than a switch full of send calls,
    /// so the escape sequences are testable.
    var sequence: String? {
        switch self {
        case .esc: return "\u{1b}"
        case .tab: return "\t"
        // CSI Z (back-tab). An iOS software keyboard cannot produce shift+tab
        // at all, and claude's own footer advertises it as the way to cycle
        // permission modes — so on a phone that mode was simply unreachable.
        case .shiftTab: return "\u{1b}[Z"
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
        // paste is not a static sequence: it goes through the view so the
        // app's bracketed-paste mode is honoured. See the handler.
        case .paste, .ctrl, .alt, .dismiss: return nil
        }
    }

    var spokenName: String {
        switch self {
        case .shiftTab: return "shift tab"
        case .pageUp: return "page up"
        case .pageDown: return "page down"
        default: return "\(self)"
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

    /// SwiftTerm's iOS view has no scroll gesture: one pan handler forwards
    /// mouse events (claude turns mouse mode on, so drags reach the app) and
    /// the other does selection, whose only scroll-ish branch sends ARROW KEYS.
    /// Nothing moves the local viewport, so the scrollback was unreachable by
    /// touch — the first gesture anyone tries on a phone.
    ///
    /// Drags the buffer 1:1 with the finger, alongside SwiftTerm's own
    /// recognizers so long-press selection and its menu keep working.
    func installScrollGesture() {
        // On a phone a drag scrolls. That has to be exclusive, because
        // SwiftTerm's own pans do two things we don't want during a scroll:
        // with mouse mode on (claude turns it on) a drag sends a CLICK at the
        // start point, which in a TUI can activate whatever is under your
        // finger; with it off, the same handler sends ARROW KEYS. Neither is
        // an acceptable side effect of scrolling, so its pans are disabled and
        // mouse reporting with them.
        //
        // Traded away: drag-to-extend a selection. Long-press still selects a
        // word and opens the menu, which is how iOS does selection anyway.
        allowMouseReporting = false
        for existing in gestureRecognizers ?? [] where existing is UIPanGestureRecognizer {
            existing.isEnabled = false
        }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    /// A drag is a SCROLL, and what that means depends on who owns the screen.
    /// This mirrors what SwiftTerm's macOS view does for a scroll wheel, which
    /// the iOS view has no equivalent of:
    ///
    /// 1. App takes wheel events (claude does) — send them, so the app scrolls
    ///    its own transcript, one notch per row of finger travel. Wheel is not
    ///    a click: this doesn't reintroduce the phantom taps that #55 removed.
    /// 2. No local scrollback and no wheel (a pager on the alt screen) — send
    ///    PAGE keys, three rows to the page.
    /// 3. Otherwise — move our own viewport, with momentum.
    ///
    /// Only case 3 was implemented, which is why dragging did nothing at all on
    /// an agent session: the alternate screen has NO scrollback by design, so
    /// there was never anything local to move.
    ///
    /// Case 2 sends Page and not arrows, learned the hard way from the desktop
    /// client: arrows at a claude prompt recall previous PROMPTS. A fallback
    /// that rewrites what you were typing is worse than one that does nothing.
    @objc private func handleScrollPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stopMomentum()
            scrollDebt = 0
        case .changed:
            // Incremental: the debt engine consumes travel, so read the
            // translation as a delta and reset it each time.
            scrollDebt += g.translation(in: self).y
            g.setTranslation(.zero, in: self)
            applyScrollDebt()
        case .ended:
            startMomentum(pointsPerSecond: g.velocity(in: self).y)
        default:
            break
        }
    }

    /// Finger travel not yet spent, in POINTS, positive when dragging DOWN —
    /// which reveals older output, like every scroll view on iOS.
    ///
    /// One accumulator for all three sinks is what makes this feel native. A
    /// slow drag would otherwise round to zero rows every frame and never move
    /// at all, and — the reason it's shaped this way — momentum can push into
    /// the same debt the finger does, so a wheel app coasts exactly like our
    /// own viewport rather than stopping dead the moment you let go. Same
    /// design as hop's web client, whose fractional carry solved this first.
    private var scrollDebt: CGFloat = 0
    private static let rowsPerPageKey = 3

    private func applyScrollDebt() {
        let terminal = getTerminal()
        let cell = max(1, bounds.height / CGFloat(max(1, terminal.rows)))
        let log = Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")

        if appTakesWheel {
            let rows = Int(scrollDebt / cell)          // truncates toward zero
            guard rows != 0 else { return }
            scrollDebt -= CGFloat(rows) * cell
            log.info("scroll \(rows > 0 ? "back" : "forward") \(abs(rows)) via wheel")
            terminal.sendResponse(text: wheelSequence(
                rows: rows, cols: terminal.cols, screenRows: terminal.rows))
        } else if terminal.getLine(row: terminal.rows) == nil {
            // No local scrollback (a pager on the alt screen): coarse keys, so
            // travel has to pile up before it's worth one.
            let pagePoints = cell * CGFloat(Self.rowsPerPageKey)
            let pages = Int(scrollDebt / pagePoints)
            guard pages != 0 else { return }
            scrollDebt -= CGFloat(pages) * pagePoints
            log.info("scroll \(pages > 0 ? "back" : "forward") \(abs(pages)) pages")
            for _ in 0..<min(abs(pages), 8) {
                keyHandler?.accessoryKey(pages > 0 ? .pageUp : .pageDown, isRepeat: true)
            }
        } else {
            let rows = Int(scrollDebt / cell)
            guard rows != 0 else { return }
            scrollDebt -= CGFloat(rows) * cell
            let target = max(0, terminal.buffer.yDisp - rows)
            if target != terminal.buffer.yDisp { scrollTo(row: target) }
        }
    }

    private var remoteMouse = RemoteMouseState()
    private var appTakesWheel: Bool { remoteMouse.takesWheel }

    func setRemoteMouse(reporting: Bool, sgr: Bool) {
        remoteMouse.seed(reporting: reporting, sgr: sgr)
    }

    func noteRemoteModes(in chunk: String) { remoteMouse.note(chunk) }

    private var momentum = ScrollMomentum()
    private var momentumLink: CADisplayLink?

    private func startMomentum(pointsPerSecond: CGFloat) {
        stopMomentum()
        guard momentum.start(pointsPerSecond: Double(pointsPerSecond)) else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum))
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }

    @objc private func stepMomentum() {
        let terminal = getTerminal()
        let wasAtTop = terminal.buffer.yDisp == 0
        guard let points = momentum.step() else { return stopMomentum() }
        scrollDebt += CGFloat(points)
        applyScrollDebt()
        // A local viewport already parked at the oldest line has nothing left
        // to reveal, and the debt would grow without bound — enough of it and
        // the flick back the other way would be swallowed doing nothing.
        let stuckAtTop = wasAtTop && points > 0 && !appTakesWheel
            && terminal.getLine(row: terminal.rows) != nil
        if stuckAtTop { stopMomentum() }
    }

    private func stopMomentum() {
        momentumLink?.invalidate()
        momentumLink = nil
        momentum.stop()
        scrollDebt = 0
    }

    private var installedTheme: Bool = false

    func applyTheme(light: Bool) {
        let theme: TerminalTheme = light ? .light : .dark
        nativeForegroundColor = theme.foreground
        nativeBackgroundColor = theme.background
        backgroundColor = theme.background
        caretColor = theme.cursor
        selectedTextBackgroundColor = theme.selection
        // installColors repaints the whole grid, so only on a real change.
        if !installedTheme || currentThemeIsLight != light {
            installedTheme = true
            currentThemeIsLight = light
            installColors(theme.ansi)
        }
    }

    private var currentThemeIsLight = false

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
        // Announce the state, don't just colour it: a sticky modifier whose
        // only signal is a background tint is invisible to VoiceOver, and to
        // any test that would catch it silently breaking.
        altButton?.accessibilityValue = armed ? "armed" : nil
        altButton?.configuration?.baseForegroundColor = armed ? .black : .white
        altButton?.configuration?.background.backgroundColor =
            armed ? .hopKeyArmed : .hopKey
    }

    // SwiftTerm exposes inputAccessoryView as a settable var — assign, don't override.
    func installAccessoryBar() {
        inputAccessoryView = makeAccessory()
    }

    func setCtrlArmed(_ armed: Bool) {
        ctrlButton?.accessibilityValue = armed ? "armed" : nil
        ctrlButton?.configuration?.baseForegroundColor = armed ? .black : .white
        ctrlButton?.configuration?.background.backgroundColor =
            armed ? .hopKeyArmed : .hopKey
    }

    private var holdKeys: [ObjectIdentifier: AccessoryKey] = [:]

    @objc private func handleKeyLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let btn = g.view as? UIButton,
              let key = holdKeys[ObjectIdentifier(btn)] else { return }
        endRepeat()          // a hold is the alternate key, not a repeat
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        keyHandler?.accessoryKey(key, isRepeat: false)
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
        if window == nil {
            endRepeat()
            stopMomentum()
        }
    }

    deinit {
        repeatTimer?.invalidate()
        momentumLink?.invalidate()      // a live CADisplayLink outlives the view
    }

    @objc private func endRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    static let accessoryHeight: CGFloat = 46

    private func makeAccessory() -> UIView {
        let bar = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: Self.accessoryHeight))
        bar.backgroundColor = .hopRaised

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
        // Only keys an iOS keyboard CANNOT produce. Dropped |, /, -, ~ and the
        // separate paste key: the first four live one layer away on the system
        // keyboard, and spending a third of a phone-width bar on them pushed
        // the arrows off-screen. `hold` is a second key on a long press —
        // shift+tab, PgUp and PgDn are real keys with no room of their own,
        // and each sits on the key it belongs to.
        // Only keys an iOS keyboard cannot produce. |, / , - and ~ are one
        // layer away on the system keyboard and were eating a third of the bar.
        //
        // Long-press alternates are ONLY on keys that don't repeat: putting
        // PgUp/PgDn on the arrows collided with hold-to-repeat, so holding ↓ to
        // walk shell history fired a page-down instead. The arrows repeat; tab
        // doesn't, so shift+tab lives there.
        //
        // Widths are tuned so esc…→ — the nine you reach for constantly — fit
        // without scrolling; paging, paste and dismiss sit just past the edge.
        let keys: [(String, AccessoryKey, CGFloat, String, AccessoryKey?)] = [
            ("esc", .esc, 40, "escape", nil),
            ("tab", .tab, 44, "tab", .shiftTab),
            ("ctrl", .ctrl, 42, "control", nil),
            ("alt", .alt, 38, "alt", nil),
            ("^C", .ctrlC, 38, "control C", nil),
            ("←", .left, 34, "left arrow", nil),
            ("↓", .down, 34, "down arrow", nil),
            ("↑", .up, 34, "up arrow", nil),
            ("→", .right, 34, "right arrow", nil),
            ("⇞", .pageUp, 38, "page up", nil),
            ("⇟", .pageDown, 38, "page down", nil),
            ("paste", .paste, 50, "paste", nil),
            ("⌄", .dismiss, 34, "hide keyboard", nil)
        ]
        for (label, key, width, spoken, hold) in keys {
            var cfg = UIButton.Configuration.filled()
            cfg.title = label
            cfg.baseForegroundColor = .white
            cfg.background.backgroundColor = .hopKey
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
            if let hold {
                // A dot is the whole affordance: quiet enough to ignore, and
                // the only honest way to say "there's more here" on a 36pt key.
                cfg.attributedTitle = AttributedString(
                    label + " ·", attributes: AttributeContainer([
                        .font: UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
                    ]))
                btn.configuration = cfg
                let press = UILongPressGestureRecognizer(target: self,
                                                         action: #selector(handleKeyLongPress(_:)))
                press.minimumPressDuration = 0.35
                btn.addGestureRecognizer(press)
                holdKeys[ObjectIdentifier(btn)] = hold
                btn.accessibilityHint = "Hold for \(hold.spokenName)"
            }
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

extension HopTermView: UIGestureRecognizerDelegate {
    /// Don't scroll out from under a selection: once one exists, dragging
    /// belongs to its handles.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        // Only gate OUR pan; leave UIView's own answer for everything else.
        guard g is UIPanGestureRecognizer else { return super.gestureRecognizerShouldBegin(g) }
        return !selectionActive
    }

    /// Coexist with the long-press and tap recognizers, which are how
    /// selection and focus still work.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
