import SwiftUI
import SwiftTerm
import TipKit
import os

// Native terminal host: SwiftTerm view + a key accessory bar above the iOS
// keyboard (Esc / Tab / sticky-Ctrl / arrows / paste — the keys the soft
// keyboard lacks), connection-state chrome, and haptic bells.
/// The window's top safe inset, read from UIKit — the same reach the
/// keyboard-frame handler already uses. Needed because the terminal now
/// extends UNDER the status bar (Jian: "the top part of the screen in the
/// terminal mode was not used"), and the floating chrome must not follow it
/// up beneath the clock.
@MainActor
func windowTopInset() -> CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.top }
        .first ?? 59
}

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
    /// Chrome is for arriving and for deciding; the terminal is for reading.
    /// Shown on arrival and on a top-strip tap, gone three seconds later.
    ///
    /// It lives in an OVERLAY now, not the navigation bar. The bar version
    /// resized the terminal on every toggle, and a terminal resize reflows
    /// the shared PTY — summoning a menu repainted the session mid-read,
    /// which Jian called out. The overlay translucently covers the top rows
    /// while it is up, briefly and on purpose: the grid underneath never
    /// moves, so showing chrome costs a glance-through instead of a reflow.
    @State private var chromeShown = true
    /// Observer mode: shrink type until the peer's full grid width fits.
    @State private var fitWidth = false
    @State private var fitTick = 0
    @State private var findOpen = false
    /// Focus lands in the find field the moment the bar opens. Without this
    /// the keyboard stays bound to the TERMINAL, and typing a search term
    /// sends it into the live session — screenshot-caught with "keyboard"
    /// sitting in a claude composer instead of the find field.
    @FocusState private var findFocused: Bool
    @State private var reconnectToken = 0
    @ObservedObject private var network = NetworkConditions.shared
    @State private var controlAction: ControlAction?
    @State private var toast: String?
    @State private var viewers: [HayClient.Viewer] = []
    @State private var collabEveryone = true
    @State private var iHoldControl = false
    @State private var lockedByOther = false
    @State private var scrolledUp = false
    /// "76×24" while a peer/default size holds the grid — the size chip.
    @State private var peerSize: String?
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
                       fitWidth: fitWidth, fitTick: fitTick,
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
                       onScroll: { scrolledUp = $0 },
                       onChromeTap: {
                           withAnimation(.easeOut(duration: 0.2)) { chromeShown.toggle() }
                       },
                       onBackSwipe: { dismiss() },
                       onFitRefresh: { fitTick += 1 },
                       onSizeState: { peerSize = $0 })
    }

    var body: some View {
        screen
            .padding(.horizontal, 2)
            // Rows begin just under the status text (probe-caught at 26:
            // row zero ran straight through the clock). ~19pt reclaimed over
            // the old safe-area start, and the band above reads as the
            // terminal's own surface instead of dead space.
            .padding(.top, 40)
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
            // PLAN.md item 1: the re-entry size lottery, made visible. The
            // chip names the size that holds the grid; the tap asks for
            // ours. A refusal (someone typed recently) re-arms it — state,
            // not magic.
            .overlay(alignment: .topTrailing) {
                if let peerSize, goneReason == nil {
                    Button {
                        controlAction = .claimSize
                    } label: {
                        Label("\(peerSize) — take mine", systemImage: "arrow.down.right.and.arrow.up.left.rectangle")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                    }
                    .tint(.hopGlow)
                    .padding(.top, windowTopInset() + 46)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                    .accessibilityLabel("Session is \(peerSize). Tap to take your size.")
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
                        .padding(.top, windowTopInset() + 6)
                        .task { try? await Task.sleep(for: .seconds(2)); self.toast = nil }
                }
            }
            .onChange(of: findOpen) { _, open in
                if open { findFocused = true }
            }
            // Landscape gives every point to the terminal — Jian's rule, and
            // the keyboard already eats half the height there. Rotating
            // dismisses the chrome even under the test-mode pin (the pin
            // exists to stop TIMERS moving the UI mid-test, not to override
            // an explicit state change); the top strip still summons it.
            .onChange(of: landscapePhone) { _, landscape in
                if landscape {
                    withAnimation(.easeOut(duration: 0.2)) { chromeShown = false }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if findOpen {
                    // Same material as the chrome pill — the last stock strip
                    // in the terminal. (Still a safeAreaInset, not an overlay:
                    // an input mode may honestly take layout space.)
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            TextField("find in scrollback", text: $findText)
                                .focused($findFocused)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(.subheadline, design: .monospaced))
                                .onChange(of: findText) { _, _ in
                                    findDirection = -1  // new query: newest match first
                                    findMisses = 0
                                    findSeq += 1
                                }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
                        Button {
                            findDirection = -1          // older
                            findSeq += 1
                        } label: {
                            Image(systemName: "chevron.up")
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                            .accessibilityLabel("Previous match")
                        Button {
                            findDirection = 1           // newer
                            findSeq += 1
                        } label: {
                            Image(systemName: "chevron.down")
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                            .accessibilityLabel("Next match")
                        Button("Done") { findFocused = false; findOpen = false; findText = "" }
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .padding(.top, windowTopInset())
                    .background(.ultraThinMaterial)
                    .overlay(alignment: .bottom) {
                        Color.white.opacity(0.06).frame(height: 0.5)
                    }
                }
            }
            // No navigation bar, EVER — not hidden-until-tapped, gone. The
            // bar's coming and going resized the terminal, and a terminal
            // resize reflows the shared PTY: summoning a menu repainted the
            // session mid-read. The chrome floats above the grid instead
            // (chromeBar below), so the terminal holds one size for the whole
            // visit and toggling chrome moves nothing.
            .toolbar(.hidden, for: .navigationBar)
            .statusBarHidden(landscapePhone)
            .overlay(alignment: .top) {
                // Suppressed once the session is gone (the ended card carries
                // its own way back), in landscape (every point is terminal),
                // and while FIND is open — both claim the top edge, and the
                // pill drew over the find bar (probe-caught: the field took
                // typing while the pill covered it).
                if chromeShown, !landscapePhone, !findOpen, goneReason == nil {
                    chromeBar
                        .transition(.move(edge: .top).combined(with: .opacity))
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
            // The route changed under us — wifi to 5G, or a dead path coming
            // back. Every open socket is already dead; waiting out a backoff
            // that has grown to 15 seconds is 15 seconds of dead screen with a
            // working network. Same guard as the foreground case: only a closed
            // socket, because each reconnect pulls a fresh snapshot.
            .onChange(of: network.pathGeneration) {
                if status == .closed { reconnectToken += 1 }
            }
            .task(id: session.internalName) {
                chromeShown = true
                // VoiceOver users keep the chrome. Hiding it trades
                // discoverability for terminal rows, and the ways back — a tap
                // on an unmarked strip, a drag toward the live edge — are
                // gestures VoiceOver cannot see. For a VoiceOver user the
                // hidden bar isn't minimal, it's GONE, and with it the back
                // button, the switcher and every terminal action.
                guard !UIAccessibility.isVoiceOverRunning else { return }
                // Under test the bar stays put. The same launch argument
                // already steadies the caret, for the same reason: XCUITest
                // resolves elements against a moving target and reports the
                // miss as whatever assertion happened to be next, which cost
                // hours here — a chrome timer was read as "menus don't open in
                // an overlay" and a working feature was reverted over it.
                guard !ProcessInfo.processInfo.arguments.contains("-hop-ui-testing") else { return }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.easeOut(duration: 0.25)) { chromeShown = false }
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
            // The strips AROUND the terminal (padding, safe areas) follow the
            // terminal's theme. hopSurface is the dark background's exact hex,
            // so dark mode is unchanged — but in light mode the white terminal
            // sat letterboxed in near-black bands, screenshot-caught.
            .background(lightTheme ? Color(uiColor: TerminalTheme.light.background)
                                   : Color.hopSurface)
            // The whole band above was reserved and empty. The grid owns it
            // now; every floating element re-anchors below the status text.
            .ignoresSafeArea(.container, edges: .top)
    }

    // MARK: floating chrome

    /// The navigation bar's replacement: back, the session title (a menu —
    /// switching sessions is the most common reason to touch chrome at all),
    /// and the actions menu. Lives in an overlay so its appearance never
    /// changes the terminal's frame.
    private var chromeBar: some View {
        HStack(spacing: 8) {
            // No back chevron. Jian flagged the pair twice: a big back
            // button beside a menu is two ways out standing shoulder to
            // shoulder. The edge swipe is the way back; the title menu
            // carries the explicit "All sessions…" for anyone who needs
            // words. (The swipe-hint tip died here too — its popover
            // ballooned over the island once the pill moved under the
            // status bar.)
            titleMenu
            Spacer(minLength: 4)
            actionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
            .allowsHitTesting(false))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        // The bar floats over the strip whose tap summons chrome — so the
        // bar itself must answer the same tap, or showing chrome would
        // consume the only gesture that hides it. Controls still win; this
        // catches taps on the bar's empty background.
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { chromeShown = false } }
        // Safari's address-bar swipe, for terminals: drag the pill sideways
        // to step through the fleet in switcher order. Horizontal-dominant
        // and 50pt of travel, so bar taps and menu touches never misfire.
        .gesture(DragGesture(minimumDistance: 25).onEnded { v in
            let dx = v.translation.width
            guard abs(dx) > 50, abs(dx) > abs(v.translation.height) * 2,
                  let next = neighborSession(model.sessions,
                                             of: session.internalName,
                                             step: dx < 0 ? 1 : -1) else { return }
            model.requestedSession = next.internalName
        })
        .padding(.horizontal, 5)
        .padding(.top, windowTopInset() + 1)
    }

    private var titleMenu: some View {
        Menu {
            Section("Switch session") {
                ForEach(switcherCandidates(model.sessions,
                                           excluding: session.internalName)) { other in
                    Button {
                        model.requestedSession = other.internalName
                    } label: {
                        Label(other.attention ? "\(other.name) ●" : other.name,
                              systemImage: other.createdBy == "agent" ? "cpu" : "terminal")
                    }
                }
                // The one explicit way out, now that the pill carries no
                // chevron: the menu caps at twelve and the fleet runs
                // twenty, so this also rescues "the session I want isn't
                // listed".
                Button { dismiss() } label: {
                    Label("All sessions…", systemImage: "square.grid.2x2")
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(status == .live ? Color.green : status == .connecting ? Color.yellow : Color.red)
                    .frame(width: 8, height: 8)
                Text(renamedTitle ?? session.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
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

    /// The old menu was twelve items in arrival order — copy next to collab
    /// next to theme, one divider doing all the explaining. Regrouped by what
    /// an item acts ON, most-reached first: the screen's content (find, copy,
    /// links), then how it's drawn (fit, size, theme), then who's here, then
    /// the connection.
    private var actionsMenu: some View {
        Menu {
            Section {
                Button { findOpen.toggle() } label: { Label("Find", systemImage: "magnifyingglass") }
                Button { NotificationCenter.default.post(name: .hopCopyScreen, object: nil) } label: {
                    Label("Copy screen", systemImage: "doc.on.doc")
                }
                Button { NotificationCenter.default.post(name: .hopCopyAll, object: nil) } label: {
                    Label("Copy all scrollback", systemImage: "doc.on.clipboard")
                }
                Button { controlAction = .links } label: {
                    Label("Open link…", systemImage: "link")
                }
            }
            Section("View") {
                // Observer mode: see the peer's whole grid width at once
                // instead of panning — and claim nothing while watching.
                Button { fitWidth.toggle(); fitTick += 1 } label: {
                    Label(fitWidth ? "Actual size" : "Fit to width",
                          systemImage: fitWidth
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left")
                }
                Button { setFont(fontSize + 1) } label: { Label("Bigger text", systemImage: "textformat.size.larger") }
                Button { setFont(fontSize - 1) } label: { Label("Smaller text", systemImage: "textformat.size.smaller") }
                Button {
                    lightTheme.toggle()
                    UserDefaults.standard.set(lightTheme, forKey: "termLight")
                } label: {
                    Label(lightTheme ? "Dark terminal" : "Light terminal",
                          systemImage: lightTheme ? "moon.fill" : "sun.max.fill")
                }
            }
            // Who else is here + who may type (hay collab model). ForEach of
            // an empty viewers list renders nothing, so the section header is
            // the only cost when you're alone.
            Section("Sharing") {
                ForEach(viewers) { v in
                    Label(v.typing ? "\(v.name) — typing" : v.name,
                          systemImage: "person.fill")
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
            }
            Section {
                Button { reconnectToken += 1 } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .accessibilityLabel("Terminal actions")
        }
    }
}

/// One find, identified by `seq` so the terminal runs it exactly once.
struct FindRequest: Equatable {
    let query: String
    let seq: Int
    let direction: Int
}

enum ControlAction { case take, release, lock, unlock, links, claimSize }

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
    /// Observer mode: shrink the glyphs until the peer's full grid width fits,
    /// and stop claiming the PTY size while doing it — a fit-width client that
    /// claimed its inflated row count would reflow the desk it is watching.
    var fitWidth = false
    /// Bumped when the room's elected size changes, so the fit font recomputes.
    var fitTick = 0
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
    var onChromeTap: () -> Void = {}
    var onBackSwipe: () -> Void = {}
    var onFitRefresh: () -> Void = {}
    /// "76×24" while a peer/default size holds the grid, nil when the grid
    /// is ours — the size chip's feed. PLAN.md item 1: the re-entry size
    /// lottery becomes visible state with a one-tap exit.
    var onSizeState: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(wsBase: model.wsBase, httpBase: model.normalizedServerURL, token: model.accessToken,
                    urlSession: model.urlSession, room: room, onToast: onToast, onLinks: onLinks,
                    onFontChange: onFontChange, onRenamed: onRenamed, onGone: onGone,
                    onPresence: onPresence, onCollab: onCollab, onScroll: onScroll,
                    onSizeState: onSizeState) { status = $0 }
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
        tv.onChromeTap = onChromeTap
        tv.onBackSwipe = onBackSwipe
        context.coordinator.onGridChange = onFitRefresh
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
        _ = fitTick     // dependency: elected-size changes re-run this update
        context.coordinator.observeOnly = fitWidth
        if !fitWidth { context.coordinator.fitNudges = 0 }
        var size = CGFloat(fontSize)
        if fitWidth {
            let cols = uiView.getTerminal().cols
            let width = uiView.bounds.width
            let advance = { (pt: CGFloat) -> CGFloat in
                ("0" as NSString).size(withAttributes:
                    [.font: UIFont.monospacedSystemFont(ofSize: pt, weight: .regular)]).width
            }
            // Analytic first guess, then measure-and-correct: glyph advances
            // round to pixel boundaries at small sizes, so pure linear scaling
            // left 84 of 90 columns fitting — measured, off by one wrap.
            size = fitFontSize(base: size, baseCellWidth: advance(size),
                               viewWidth: width, gridCols: cols)
            // Each nudge is a 3% shrink on top of the analytic guess, applied
            // until SwiftTerm reports the elected column count actually fits.
            size = max(4, size * CGFloat(pow(0.97, Double(context.coordinator.fitNudges))))
            for _ in 0..<3 {
                let w = advance(size) * CGFloat(cols)
                if w <= width || size <= 4 { break }
                size = max(4, size * width / w * 0.995)
            }
            HopTermView.log.info("fit: cols=\(cols) width=\(Int(width)) -> \(size)pt")
        }
        // Only when it changed: setting a font re-lays-out the terminal, and
        // updateUIView runs on every SwiftUI pass — an unconditional set here
        // is a layout loop waiting for a trigger.
        if abs(uiView.font.pointSize - size) > 0.1 {
            uiView.font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
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

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate, AccessoryKeyHandler {
        /// A terminal holds a 5000-line buffer and a socket. If leaving a
        /// session ever stops releasing this, a phone that opens twenty
        /// sessions in a session accumulates twenty of them — and the only
        /// symptom is the app being killed for memory, long after the cause.
        /// So the release is logged, and its absence is the signal.
        deinit {
            Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                .info("terminal released")
        }

        private let client = HayClient()
        private weak var view: HopTermView?
        private let wsBase: String
        private let httpBase: String
        private let token: String?
        private var token_: String? { token }
        private let urlSession: URLSession
        private let room: String
        private let pushStatus: (TerminalHostView.ConnState) -> Void
        let onSizeState: (String?) -> Void
        private var isLive = false
        /// A peer holds the PTY size (we adopted theirs). While true, layout
        /// changes do NOT re-send our fitted size: every keyboard show/hide
        /// was sending a resize the server rejected, which re-broadcast
        /// active_size, which re-adopted — a 3-second flap of 51↔90 columns
        /// for as long as a desk held the session. hop's rule is that size
        /// follows TYPING, so the reclaim happens on the next real keystroke,
        /// not on layout noise.
        private var peerHoldsSize = false
        /// Observer mode (fit-width): watch at the peer's geometry, claim
        /// nothing — not even on typing. You chose to see their whole grid;
        /// keystrokes go into THEIR layout, which is what answering a prompt
        /// on the desk's screen means.
        var observeOnly = false
        var onGridChange: () -> Void = {}
        /// The size the room elected, and how many times fit-width has nudged
        /// the font smaller to reach it. Font metrics differ between our
        /// measurement and SwiftTerm's rounding — measured: the analytic size
        /// fit 84 of 90 columns — so the fit converges on SwiftTerm's own
        /// reported column count instead of trusting any advance calculation.
        var electedCols = 0
        var electedRows = 0
        var fitNudges = 0
        /// Latched when hop says the session is over. Reconnecting after that
        /// does not reattach — it creates a new session wearing the same name.
        private var sessionEnded = false
        private var controlLocked = false
        private var lastLockedToast = Date.distantPast
        private var lastDeadToast = Date.distantPast

        private var pending = PendingInput()
        private var lastReclaimAt = Date.distantPast

        /// Every keystroke goes through here: straight out on a live socket,
        /// buffered otherwise. A terminal's echo comes from the SERVER, so
        /// silence during an outage reads as a frozen app — hence the toast,
        /// throttled, since a burst of typing would be a burst of toasts.
        private func deliver(_ text: String) {
            guard !text.isEmpty else { return }
            if isLive {
                // Typing is how a size is reclaimed in hop. If a peer held the
                // grid, this keystroke makes us the recent typist — send our
                // fitted size along with it so the terminal snaps back to this
                // screen's shape the moment the user engages.
                //
                // The flag is NOT cleared here. Clearing on send was a latch:
                // the server refuses a reclaim while the peer typed <60s ago,
                // the refusal rebroadcast repeats the size we had already
                // adopted (so the adopt path saw nothing new), and with the
                // flag optimistically false every later keystroke skipped
                // reclaiming — measured on device as "never autofits back no
                // matter how much I type". Now the reclaim retries with each
                // keystroke, throttled, and only a CONFIRMED win (active_size
                // matching our fitted grid) clears the flag.
                if peerHoldsSize, !observeOnly, fittedCols > 1, fittedRows > 1,
                   Date().timeIntervalSince(lastReclaimAt) > 1 {
                    lastReclaimAt = Date()
                    client.sendResize(cols: fittedCols, rows: fittedRows)
                }
                client.sendInput(text)
                markTyping()
                return
            }
            // A session that ENDED is not coming back, so buffering keystrokes
            // for it promises a replay that can never happen — and the whole
            // point of that message is that the promise is kept. Say the true
            // thing instead.
            guard !sessionEnded else {
                if Date().timeIntervalSince(lastDeadToast) > 2 {
                    lastDeadToast = Date()
                    onToast("Session has ended")
                }
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
             onSizeState: @escaping (String?) -> Void,
             setStatus: @escaping (TerminalHostView.ConnState) -> Void) {
            self.onScroll = onScroll
            self.onSizeState = onSizeState
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
                            .info("scrollback reachable \(depth) lines, altScreen=\(self.view?.remoteAltScreen == true)")
                    }
                case .output(let data):
                    tv.noteRemoteModes(in: data)
                    tv.feed(text: data)
                    // After the feed's display pass: SwiftTerm re-pins the
                    // offset on output, which would undo a pan while the desk
                    // is typing — and yank a scrolled-up reader back to the
                    // live edge in any session that prints steadily.
                    DispatchQueue.main.async { [weak tv, weak self] in
                        tv?.reapplyPan()
                        // The pin fired onScroll(false) through scrolled();
                        // the restore doesn't reliably fire it back. Say the
                        // true thing ourselves or the Live pill dies the
                        // first second a ticking session is read from
                        // history.
                        if tv?.restoreHistoryAnchor() == true { self?.onScroll(true) }
                    }
                case .snapshot(let data, let alternateScreen, let cursorHidden,
                               let mouseReporting, let mouseSgr):
                    self.snapshotLanded = true
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
                    tv.sawScrollback = false     // a reset terminal has none
                    // Back to the size this screen actually fits. The fast
                    // paint deliberately resizes the grid to the session's real
                    // size so the pre-snapshot screen isn't wrapped into mush,
                    // and nothing puts it back: SwiftTerm re-fits only when its
                    // BOUNDS change, so that grid survives until the keyboard
                    // happens to appear. A grid taller than the view has its
                    // bottom rows outside the bounds; a shorter one leaves the
                    // screen underfilled. Measured: usually the snapshot beats
                    // the fast paint and this is a no-op, which is why it never
                    // showed. On a slow link the fast paint lands first.
                    if self.fittedCols > 1, self.fittedRows > 1,
                       tv.getTerminal().cols != self.fittedCols
                        || tv.getTerminal().rows != self.fittedRows {
                        tv.getTerminal().resize(cols: self.fittedCols, rows: self.fittedRows)
                    }
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
                    tv.setRemoteModes(altScreen: alternateScreen,
                                      mouseReporting: mouseReporting, mouseSgr: mouseSgr)
                    tv.feed(text: data)
                case .presence(let list):
                    self.onPresence(list)
                case .collab(let everyone, let controllerId):
                    let mine = controllerId != nil && controllerId == self.client.clientId
                    self.controlLocked = !everyone && !mine && controllerId != nil
                    self.onCollab(everyone, mine, self.controlLocked)
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
                    // ADOPTED, the way hop's mobile web does it (Jian's call —
                    // this replaces #96's refuse-and-reflow). One PTY has one
                    // size; when a peer holds it, the choice is between
                    // wrapping their 80-column output into our 51-column grid
                    // (mush) or drawing their grid at full size and PANNING
                    // over it. The web's manual mode picks panning, and so do
                    // we: HopTermView turns drags into 1:1 panning whenever
                    // the grid is bigger than what fits, which is also what
                    // makes the clipped region — claude's input box lives at
                    // the bottom — reachable rather than lost.
                    //
                    // Self-heals in both directions: our next claim (attach,
                    // or a keyboard-driven refit) takes the size back, and
                    // their next keystroke reclaims it.
                    let mine = tv.getTerminal()
                    self.electedCols = cols
                    self.electedRows = rows
                    if cols == self.fittedCols && rows == self.fittedRows {
                        self.peerHoldsSize = false      // our size won; normal rules
                        self.onSizeState(nil)
                        self.stopReclaimRetry()
                    } else if mine.cols != cols || mine.rows != rows {
                        Logger(subsystem: "io.zhoulab.hop.spike", category: "layout")
                            .info("room elected \(cols)x\(rows), we draw \(tv.drawnCols)x\(tv.drawnRows) — adopting; drags pan")
                        self.peerHoldsSize = true
                        self.onSizeState("\(cols)×\(rows)")
                        self.startReclaimRetry()
                        mine.resize(cols: cols, rows: rows)
                        self.onGridChange()
                    } else {
                        // Grid already drawn at the peer's size — this is what
                        // a REFUSED reclaim's rebroadcast looks like. Re-arm,
                        // so the next keystroke keeps trying.
                        self.peerHoldsSize = true
                        self.onSizeState("\(cols)×\(rows)")
                        if self.reclaimTimer == nil { self.startReclaimRetry() }
                    }
                case .ended(let message):
                    // The session is GONE, and reconnecting would not find it —
                    // it would CREATE it. hop makes a room on demand for any
                    // attach, so the automatic retry answered "this session
                    // ended" by bringing a brand-new shell back under the same
                    // name. Kill a session at your desk with your phone open on
                    // it, and the phone quietly resurrected it. Measured: the
                    // fleet went from 19 sessions to 20.
                    //
                    // hop's web client has always known this — it sets
                    // shouldReconnect = false on session_ended.
                    self.sessionEnded = true
                    self.retryTask?.cancel()
                    self.retryTask = nil
                    // Put the keyboard away: there is nothing to type into, and
                    // leaving it up invites typing into a session that is gone.
                    _ = tv.resignFirstResponder()
                    self.setStatus(.closed)
                    self.onGone(message)
                    tv.feed(text: "\r\n\u{1b}[2m[\(message)]\u{1b}[0m\r\n")
                case .failed(let reason, let permanent):
                    // After a known end, the socket closing is a consequence,
                    // not news. Saying "connection lost" under "session
                    // terminated" reads as a second, unrelated problem.
                    if self.sessionEnded { return }
                    self.setStatus(.closed)
                    if permanent { self.onGone(reason) }
                    tv.feed(text: "\r\n\u{1b}[31m[\(reason)]\u{1b}[0m\r\n")
                    // A gone room or a rejected identity won't fix itself.
                    if !permanent { self.scheduleRetry() }
                case .closed:
                    if self.sessionEnded { return }
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
            case .claimSize:
                // The chip's tap: ask for our fitted size. The election may
                // refuse (someone typed recently) — the refusal rebroadcast
                // re-arms the chip, which is the honest answer.
                if fittedCols > 1, fittedRows > 1 {
                    client.sendResize(cols: fittedCols, rows: fittedRows)
                }
            }
        }

        /// Set once the authoritative replay lands, so the fast paint below
        /// can never scribble over it if it loses the race.
        private var snapshotLanded = false
        /// The palette this view is rendering, mirrored from SwiftUI state so
        /// the room can be told the background a TUI should theme itself for.
        ///
        /// Pushed straight into the client on every change, rather than read at
        /// connect time: there are THREE connect paths (attach, the automatic
        /// retry, and reconnectIfNeeded) and only attach was setting it. After
        /// toggling the terminal to light, every later reconnect went on
        /// announcing the dark background — and since hop has no runtime
        /// message for this, the room never learned otherwise for the life of
        /// the screen. Claude Code picks its theme from what the terminal
        /// REPORTS, so the answer being stale is the whole bug hop fixed
        /// server-side in 2522c3e, arriving from the other end.
        var themeIsLight = false {
            didSet { client.theme = themeIsLight ? .light : .dark }
        }

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
                // Coerced for the same reason every other number here is: a
                // cast that yields nil skips the resize silently, and the
                // symptom is the wrapped mush this code exists to prevent.
                if let cols = jsonInt(obj["cols"]), let rows = jsonInt(obj["rows"]),
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
            stopReclaimRetry()
            typingTimer?.invalidate()
            if typingActive { client.sendTyping(false) }
            retryTask?.cancel()
            NotificationCenter.default.removeObserver(self)
            client.close()
        }

        /// Reconnect on our own with backoff (1s, 2s, 4s, 8s, capped at 15s)
        /// so a tunnel blip or a phone waking from sleep heals itself.
        private func scheduleRetry() {
            guard alive, !sessionEnded, retryTask == nil else { return }
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
            // Every reconnect path runs through here — the manual menu item,
            // returning to the foreground, and a route change. None of them
            // should resurrect a session that ended; the way back is the list.
            guard !sessionEnded else { lastReconnectToken = token; return }
            guard token != lastReconnectToken else { return }
            lastReconnectToken = token
            retryTask?.cancel()
            retryTask = nil
            retryAttempt = 0
            client.close()
            setStatus(.connecting)
            snapshotLanded = false
            claimed = false
            fastPaint(room: room)
            // Ask whether the session still EXISTS before attaching to it.
            //
            // The sibling of the resurrection bug: if the phone is in a pocket
            // when a session is killed, it never receives session_ended, so
            // nothing is latched — and returning to the app reconnects, which
            // for hop means CREATING the room again. Same zombie, different
            // door.
            //
            // The list is refreshed rather than trusted, because the stale copy
            // is exactly what would still contain the dead session. If the
            // refresh fails, or nothing has ever been fetched, this proceeds:
            // refusing to reconnect on no evidence would be worse than the bug.
            Task { @MainActor [weak self] in
                await AppModel.shared.refreshSessions(silent: true)
                guard let self, self.alive, !self.sessionEnded, let tv = self.view else { return }
                let known = AppModel.shared.sessions
                if !known.isEmpty, !known.contains(where: { $0.internalName == self.room }) {
                    self.sessionEnded = true
                    self.setStatus(.closed)
                    self.onGone("Session ended while the app was away")
                    _ = tv.resignFirstResponder()
                    return
                }
                let t = tv.getTerminal()
                self.client.connect(base: self.wsBase, httpBase: self.httpBase, room: self.room,
                                    cols: t.cols, rows: t.rows,
                                    token: self.token_, using: self.urlSession)
            }
        }

        @objc func jumpToLive() {
            guard let tv = view else { return }
            // A user scroll like any other — the flag lets scrolled() clear
            // the anchor, or the next feed would drag us back into history.
            tv.userScrollInFlight = true
            // Scroll past the end; SwiftTerm clamps to the live edge.
            tv.scrollTo(row: Int.max / 2)
            tv.historyAnchor = nil          // belt for the clamp's braces
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
            let text = lines.joined(separator: "\n")
            UIPasteboard.general.string = text
            HopTermView.log.info("copy screen: \(text.count) chars, \(lines.count) lines")
            onToast(snapshotLanded ? "Screen copied" : "Copied — screen still syncing")
        }

        @objc func copyAll() {
            guard let tv = view else { return }
            let data = tv.getTerminal().getBufferAsData()
            let text = String(data: data, encoding: .utf8) ?? ""
            UIPasteboard.general.string = text
            HopTermView.log.info("copy all: \(text.count) chars")
            // The full history arrives with the snapshot, which can still be in
            // flight in the first seconds after opening — copying then LOOKS
            // complete and silently isn't (measured: 300 chars of a session
            // whose history was 453). Say so instead of letting it lie.
            onToast(snapshotLanded ? "Scrollback copied" : "Copied — history still syncing")
        }

        // ── AccessoryKeyHandler ──

        /// A scroll goes straight out or not at all, and never through the
        /// keystroke path. Two reasons, both found by following what deliver()
        /// does with it:
        ///
        /// It BUFFERS through an outage. A flick queues hundreds of wheel
        /// events; fifteen seconds later the connection returns and dumps them
        /// all at the agent, which scrolls off to somewhere you didn't ask for
        /// while you're reading something else. Keystrokes are worth replaying
        /// because you meant them; a scroll is about NOW, and a stale one is
        /// just noise.
        ///
        /// It also MARKS TYPING, which tells every other client watching this
        /// session that you're typing when you're only reading.
        func scrollInput(_ text: String) {
            guard !text.isEmpty else { return }
            let log = HopTermView.log
            guard isLive else { return log.info("scroll dropped, socket down") }
            // Someone else is driving. The server rejects every input from a
            // non-controller and answers each one with "Control is locked", so
            // a single flick would fire fifty doomed messages and fifty
            // rejections — pinning that toast for the whole coast, for trying
            // to READ. Say it once per gesture instead, and send nothing.
            guard !controlLocked else {
                log.info("scroll dropped, control locked")
                if Date().timeIntervalSince(lastLockedToast) > 2 {
                    lastLockedToast = Date()
                    onToast("Control is locked — take control to scroll")
                }
                return
            }
            log.info("scroll sent \(text.count) bytes")
            client.sendInput(text)
        }

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

        /// Resizes are held until this is true. Opening a session used to send
        /// TWO: the claim at the pre-keyboard height, then another when the
        /// keyboard appeared and took half the screen. One PTY means everyone
        /// reflows both times — a desk terminal redrawing twice because someone
        /// glanced at their phone.
        private var claimed = false

        /// The wake-path heal (PLAN.md item 1): while the app is FOREGROUND
        /// and a peer/default size holds the grid, re-assert the attach
        /// intent every few seconds. The server refuses while anyone typed
        /// inside the idle window and grants the moment they lapse — so the
        /// size converges to this screen without a tap, and a pocketed
        /// phone can't steal (backgrounded apps run no timers here).
        /// Returning to an open session IS the same intent attaching is.
        private var reclaimTimer: Timer?

        private func startReclaimRetry() {
            reclaimTimer?.invalidate()
            reclaimTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                // Main-actor by assertion, the #112c pattern: traps loudly if
                // the scheduling assumption ever breaks.
                MainActor.assumeIsolated {
                    guard let self, self.peerHoldsSize, !self.observeOnly,
                          UIApplication.shared.applicationState == .active,
                          self.fittedCols > 1, self.fittedRows > 1 else { return }
                    self.client.sendResize(cols: self.fittedCols, rows: self.fittedRows)
                }
            }
        }

        private func stopReclaimRetry() {
            reclaimTimer?.invalidate()
            reclaimTimer = nil
        }

        private func claimSizeOnAttach() {
            // Let the keyboard's layout land first, then claim once at the
            // size we'll actually keep.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.sendAttachClaim()
            }
        }

        private func sendAttachClaim() {
            guard !claimed, !observeOnly else { return }
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
            view?.drawnRows = newRows
            view?.drawnCols = newCols
            // Observer mode's convergence: a font change refits the terminal
            // locally, and if fewer columns fit than the room elected, the
            // adopted grid has been silently defeated. Nudge the font smaller
            // (bounded) until SwiftTerm itself reports enough columns, then
            // snap the grid back to the exact elected size.
            if observeOnly, electedCols > 1 {
                if newCols < electedCols, fitNudges < 8 {
                    fitNudges += 1
                    DispatchQueue.main.async { self.onGridChange() }
                } else if newCols != electedCols {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.observeOnly,
                              let t = self.view?.getTerminal(),
                              t.cols != self.electedCols else { return }
                        t.resize(cols: self.electedCols, rows: self.electedRows)
                    }
                }
            }
            // Before the claim, record only. Sending now would reshape the PTY
            // at a height the keyboard is about to take away. Peer-held and
            // observer mode both suppress the send: one borrows the geometry
            // until typing reclaims it, the other borrows it on purpose.
            guard claimed, !peerHoldsSize, !observeOnly else { return }
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
            let hv = source as? HopTermView
            if t.buffer.yDisp > 0 { hv?.sawScrollback = true }
            let hasHistory = t.buffer.yDisp > 0 || hv?.sawScrollback == true
            let inHistory = hasHistory && position < 0.999
            onScroll(inHistory)
            // Only USER scrolls may move the anchor. SwiftTerm's live-edge
            // pin arrives through this same callback, and letting it write
            // cleared the anchor the moment any output landed.
            if let hv = source as? HopTermView, hv.userScrollInFlight {
                hv.userScrollInFlight = false
                hv.historyAnchor = inHistory ? t.buffer.yDisp : nil
            }
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
enum AccessoryKey: Equatable {
    case esc, tab, shiftTab, ctrl, alt, ctrlC, up, down, left, right
    case pipe, slash, dash, tilde, pageUp, pageDown, paste, dismiss, backspace
    /// A control chord from the ctrl key's hold-palette: one gesture sends
    /// ^R instead of arm-ctrl-then-find-R on the system keyboard.
    case ctrlCombo(Character)

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
        // 0x7f — what the system delete sends here. This key was removed once
        // on the belief that the system delete auto-repeats on hardware; it
        // does not. The "it repeats now" observation was made on a build where
        // THIS key sat one row above the system delete — two ⌫ glyphs, one
        // thumb. Hold-to-delete vanished the release after the removal.
        case .backspace: return "\u{7f}"
        // Same masking the armed-ctrl path applies to typed letters.
        case .ctrlCombo(let ch):
            guard let ascii = ch.lowercased().first?.asciiValue,
                  ascii >= 0x61, ascii <= 0x7a else { return nil }
            return String(UnicodeScalar(ascii & 0x1f))
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
        case .ctrlCombo(let ch): return "control \(ch)"
        case .backspace: return "backspace"
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
        // Backspace repeats — it is the ONLY delete that can: iOS never
        // auto-repeats deleteBackward for a custom key-input view.
        case .up, .down, .left, .right, .pageUp, .pageDown, .backspace: return true
        default: return false
        }
    }
}
/// Main-isolated: its only implementer is the Coordinator, and every call
/// site is a touch event or a key press.
@MainActor
protocol AccessoryKeyHandler: AnyObject {
    func accessoryKey(_ key: AccessoryKey, isRepeat: Bool)
    /// Scrolling, which is NOT typing — see the implementation for why that
    /// distinction has to exist at all.
    func scrollInput(_ text: String)
}
extension AccessoryKeyHandler {
    func accessoryKey(_ key: AccessoryKey) { accessoryKey(key, isRepeat: false) }
}

final class HopTermView: TerminalView {
    /// Built once. The scroll path below runs on every frame of a coast — up
    /// to 120 a second on a ProMotion phone — and constructing a Logger per
    /// call is work done for a line that is usually disabled.
    static let log = Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")

    /// Summons or dismisses the chrome. The top strip is where anyone reaches
    /// for controls, and the one place a tap is not meant as "give me the
    /// keyboard".
    var onChromeTap: (() -> Void)?
    private weak var chromeTap: UITapGestureRecognizer?
    /// Big enough for a thumb, small enough not to steal taps meant for the
    /// first line of output. The grid extends under the status bar now, so
    /// the strip must too — a fixed 46 left the tappable band almost
    /// entirely inside the status area (probe-caught: the summon tap fell
    /// through to the keyboard).
    static var chromeStrip: CGFloat { windowTopInset() + 46 }

    @objc private func handleChromeTap(_ g: UITapGestureRecognizer) { onChromeTap?() }

    /// The way OUT, now that the terminal never shows a navigation bar.
    /// SwiftUI keeps its interactive pop DISABLED for a bar-less screen — no
    /// delegate trick re-arms it (measured: delegate claimed, isEnabled
    /// forced true every layout, and the edge swipe still scrolled the
    /// session instead of leaving it). So the terminal carries its own edge
    /// recognizer. The scroll pan already yields to any screen-edge pan by
    /// class, and the pop happens the moment the edge drag begins — the
    /// discrete animation, not UIKit's finger-tracked one, which is the
    /// price of owning the gesture.
    var onBackSwipe: (() -> Void)?

    @objc private func handleBackSwipe(_ g: UIScreenEdgePanGestureRecognizer) {
        if g.state == .began { onBackSwipe?() }
    }

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
        // The top strip belongs to the chrome: it is where anyone reaches for
        // controls, and it is the one place a tap is not meant as "give me the
        // keyboard".
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleChromeTap))
        tap.delegate = self
        addGestureRecognizer(tap)
        chromeTap = tap
        let back = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleBackSwipe))
        back.edges = .left
        addGestureRecognizer(back)
    }

    /// A drag is a SCROLL, and what that means depends on who owns the screen.
    /// This mirrors what SwiftTerm's macOS view does for a scroll wheel, which
    /// the iOS view has no equivalent of:
    ///
    /// 1. App owns the screen and takes wheel events (claude does) — send
    ///    them, so the app scrolls its own transcript, one notch per row of
    ///    finger travel. Wheel is not a click: this doesn't reintroduce the
    ///    phantom taps that #55 removed.
    /// 2. App owns the screen but won't take wheel (a pager) — send PAGE keys,
    ///    three rows to the page.
    /// 3. Nobody else owns the screen — move our own viewport, with momentum.
    ///
    /// Only case 3 was implemented, which is why dragging did nothing at all on
    /// an agent session: the alternate screen has NO scrollback by design, so
    /// there was never anything local to move.
    ///
    /// Case 2 sends Page and not arrows, learned the hard way from the desktop
    /// client: arrows at a claude prompt recall previous PROMPTS. A fallback
    /// that rewrites what you were typing is worse than one that does nothing.
    /// Which case applies is `scrollSink`, decided by who owns the screen.
    @objc private func handleScrollPan(_ g: UIPanGestureRecognizer) {
        if !peerSizedGrid { panExtra = .zero }
        if peerSizedGrid {
            // Panning, not scrolling: the content moves with the finger, both
            // axes, and momentum carries it — the grid is a surface here.
            switch g.state {
            case .began:
                stopMomentum()
            case .changed:
                let t = g.translation(in: self)
                g.setTranslation(.zero, in: self)
                panBy(dx: -t.x, dy: -t.y)
            case .ended:
                let v = g.velocity(in: self)
                startPanMomentum(vx: -v.x, vy: -v.y)
            default:
                break
            }
            return
        }
        switch g.state {
        case .began:
            stopMomentum()
            scrollDebt = 0
            gestureSink = sink
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

    /// One sink per GESTURE. The live `sink` is parsed out of the output
    /// stream, and claude toggles those modes as it redraws — re-reading it
    /// per tick could split a single drag between "wheel to the app" and
    /// "move the local viewport": both scrolled at once, intermittently
    /// (measured on device by Jian, mechanism confirmed in code). Latched at
    /// touch-down and held through the coast; when the mode changes UNDER a
    /// gesture the gesture ends rather than switching, because switching
    /// mid-coast would also fire SGR wheel bytes at an app that just stopped
    /// listening — and those arrive as typed garbage.
    private var gestureSink: ScrollSink?

    private func applyScrollDebt() {
        let terminal = getTerminal()
        let cell = drawnCellHeight(viewHeight: bounds.height,
                                   drawnRows: drawnRows, terminalRows: terminal.rows)
        let log = Self.log

        if gestureSink == nil { gestureSink = sink }   // momentum-only entry
        guard let gs = gestureSink else { return }
        if gs != sink {
            log.info("scroll gesture ended: remote mode changed under it")
            stopMomentum()
            return
        }

        switch gs {
        case .wheel:
            let rows = Int(scrollDebt / cell)          // truncates toward zero
            guard rows != 0 else { return }
            scrollDebt -= CGFloat(rows) * cell
            log.debug("scroll \(rows > 0 ? "back" : "forward") \(abs(rows)) via wheel")
            keyHandler?.scrollInput(wheelSequence(
                rows: rows, cols: terminal.cols, screenRows: terminal.rows))
        case .pageKeys:
            // Coarse keys, so travel has to pile up before it's worth one.
            let pagePoints = cell * CGFloat(Self.rowsPerPageKey)
            let pages = Int(scrollDebt / pagePoints)
            guard pages != 0 else { return }
            scrollDebt -= CGFloat(pages) * pagePoints
            log.debug("scroll \(pages > 0 ? "back" : "forward") \(abs(pages)) pages")
            if let key = (pages > 0 ? AccessoryKey.pageUp : .pageDown).sequence {
                keyHandler?.scrollInput(String(repeating: key, count: min(abs(pages), 8)))
            }
        case .viewport:
            let rows = Int(scrollDebt / cell)
            guard rows != 0 else { return }
            scrollDebt -= CGFloat(rows) * cell
            let target = max(0, terminal.buffer.yDisp - rows)
            if target != terminal.buffer.yDisp {
                userScrollInFlight = true
                scrollTo(row: target)
            }
        }
    }

    /// What the view actually draws, which is not always what the terminal
    /// says — see drawnCellHeight. Pushed in from SwiftTerm's sizeChanged.
    var drawnRows = 0
    var drawnCols = 0

    /// The user's place in HISTORY, held against the stream. SwiftTerm pins
    /// the viewport to the live edge on every feed — fine when reading live,
    /// hostile when scrolled up in a session that prints every second
    /// (music's training loop yanked the view back within a line of any
    /// scroll; Jian's "scrolling bug still exists for some sessions").
    /// Maintained by the scrolled() delegate: set while in history, nil at
    /// the live edge — so Jump to Live, find, drags and momentum all keep it
    /// honest without special cases.
    var historyAnchor: Int?
    /// Whether this terminal has EVER had scrollback — latched from observed
    /// yDisp motion. The old probe (getLine one row past the viewport)
    /// returns nil in current SwiftTerm regardless of scrollback, which
    /// killed the Live pill for every plain session and let the drag test
    /// skip forever ("no scrollback") while masking it. yDisp > 0 is truth
    /// the API can't misreport; the latch covers the top-of-history moment
    /// where yDisp legitimately returns to 0.
    var sawScrollback = false
    /// True for the beat between a USER-initiated scroll and its scrolled()
    /// callback. SwiftTerm's own live-edge pin fires the same callback, and
    /// without this flag the pin CLEARED the anchor before the post-feed
    /// restore could use it — the fix defeating itself, probe-caught.
    var userScrollInFlight = false

    /// Put the viewport back where the reader left it, after a feed's
    /// display pass re-pinned it. Returns whether an anchor is HELD, so the
    /// caller can keep the Live pill honest — scrollTo does not reliably
    /// fire the scrolled() delegate (jumpToLive's manual onScroll(false)
    /// was already compensating for the same gap).
    @discardableResult
    func restoreHistoryAnchor() -> Bool {
        guard let anchor = historyAnchor else { return false }
        if getTerminal().buffer.yDisp != anchor { scrollTo(row: anchor) }
        return true
    }

    /// A peer owns the PTY size and the grid is bigger than this view can
    /// draw. In this state a drag PANS over the full grid, 1:1 with the
    /// finger — the same behaviour as hop's mobile web. Scroll-as-wheel and
    /// scrollback come back the moment the grid fits again.
    var peerSizedGrid: Bool {
        guard drawnRows > 0, drawnCols > 0 else { return false }
        let t = getTerminal()
        return t.rows > drawnRows || t.cols > drawnCols
    }

    /// Where the user has panned to, as an offset from the position SwiftTerm
    /// keeps trying to restore: x from the left edge, y below the live row.
    ///
    /// SwiftTerm's updateScroller runs on EVERY output and pins the offset
    /// back to x=0 / the live row — measured: a horizontal pan was undone
    /// within a keystroke of lifting the finger. Storing the pan as a delta
    /// and re-applying it after output is what makes panning stick while the
    /// desk keeps typing. Vertical keeps its terminal semantics: panning up
    /// into history is ordinary scrollback (SwiftTerm preserves it), and the
    /// extra below the live row is the slice of the peer's screen that does
    /// not fit — where claude's input box lives.
    private var panExtra: CGPoint = .zero

    /// SwiftTerm recomputes contentSize lazily (updateScroller), and after a
    /// programmatic resize it can lag at the OLD grid — measured: a 90-column
    /// grid still reported contentW=391 (51 columns' worth), so maxX was zero
    /// and every pan clamped to nothing. The grid's true extent is knowable
    /// from what we draw, so make the scroll surface match it before panning.
    private func ensureGridContentSize() {
        guard drawnCols > 0, drawnRows > 0 else { return }
        let t = getTerminal()
        let cellW = bounds.width / CGFloat(drawnCols)
        let cellH = drawnCellHeight(viewHeight: bounds.height,
                                    drawnRows: drawnRows, terminalRows: t.rows)
        let gridW = cellW * CGFloat(t.cols)
        let liveBottom = (CGFloat(t.buffer.yDisp) + CGFloat(t.rows)) * cellH
        if contentSize.width < gridW || contentSize.height < liveBottom {
            contentSize = CGSize(width: max(contentSize.width, gridW),
                                 height: max(contentSize.height, liveBottom))
        }
    }

    /// Move the visible window over the grid, clamped to its edges.
    private func panBy(dx: CGFloat, dy: CGFloat) {
        ensureGridContentSize()
        let maxX = max(0, contentSize.width - bounds.width)
        let maxY = max(0, contentSize.height - bounds.height)
        let p = CGPoint(x: min(max(0, contentOffset.x + dx), maxX),
                        y: min(max(0, contentOffset.y + dy), maxY))
        contentOffset = p
        let cell = drawnCellHeight(viewHeight: bounds.height,
                                   drawnRows: drawnRows, terminalRows: getTerminal().rows)
        let liveTop = CGFloat(getTerminal().buffer.yDisp) * cell
        panExtra = CGPoint(x: p.x, y: max(0, p.y - liveTop))
    }

    /// Called after output lands: SwiftTerm has just pinned the offset home,
    /// so put the user's pan back on top of wherever it pinned to.
    func reapplyPan() {
        guard peerSizedGrid, panExtra != .zero else { return }
        ensureGridContentSize()
        let maxX = max(0, contentSize.width - bounds.width)
        let maxY = max(0, contentSize.height - bounds.height)
        let target = CGPoint(x: min(panExtra.x, maxX),
                             y: min(contentOffset.y + panExtra.y, maxY))
        if target != contentOffset { contentOffset = target }
    }

    private var remote = RemoteModes()
    /// The live value, for diagnostics: the snapshot's flag goes stale the
    /// moment the app switches screens.
    var remoteAltScreen: Bool { remote.altScreen }
    private var sink: ScrollSink {
        scrollSink(altScreen: remote.altScreen, takesWheel: remote.takesWheel)
    }

    func setRemoteModes(altScreen: Bool, mouseReporting: Bool, mouseSgr: Bool) {
        remote.seed(altScreen: altScreen, mouseReporting: mouseReporting, mouseSgr: mouseSgr)
    }

    func noteRemoteModes(in chunk: String) { remote.note(chunk) }

    private var momentum = ScrollMomentum()
    /// The pan's two axes decay on the same curve the scroll uses; `panActive`
    /// is which mode the shared display link is serving.
    private var panMomentumX = ScrollMomentum()
    private var panMomentumY = ScrollMomentum()
    private var panActive = false
    private var momentumLink: CADisplayLink?

    private func startPanMomentum(vx: CGFloat, vy: CGFloat) {
        stopMomentum()
        let x = panMomentumX.start(pointsPerSecond: Double(vx))
        let y = panMomentumY.start(pointsPerSecond: Double(vy))
        guard x || y else { return }
        panActive = true
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }
    /// A finger down stops the coast even if no recognizer claims the touch.
    /// The recognizers are asked FIRST (see gestureRecognizerShouldBegin), so
    /// by the time this runs the brake has usually already happened — which is
    /// exactly why the decision can't live here: a flag set in touchesBegan is
    /// set too late for the tap that is already being decided.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if momentumLink != nil { stopMomentum() }
        super.touchesBegan(touches, with: event)
    }

    private func startMomentum(pointsPerSecond: CGFloat) {
        stopMomentum()
        guard momentum.start(pointsPerSecond: Double(pointsPerSecond)) else { return }
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum(_:)))
        link.add(to: .main, forMode: .common)
        momentumLink = link
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        let terminal = getTerminal()
        let wasAtTop = terminal.buffer.yDisp == 0
        // The frame's real duration, so the glide is the same length in
        // SECONDS at 60Hz and at 120Hz. Clamped because a stalled frame — the
        // main thread parsing a burst of output — would otherwise spend a
        // quarter second of travel in one go.
        let elapsed = min(max(link.targetTimestamp - link.timestamp, 1.0 / 240), 1.0 / 20)
        if panActive {
            let dx = panMomentumX.step(elapsed: elapsed) ?? 0
            let dy = panMomentumY.step(elapsed: elapsed) ?? 0
            guard dx != 0 || dy != 0 else { return stopMomentum() }
            let before = contentOffset
            panBy(dx: CGFloat(dx), dy: CGFloat(dy))
            if contentOffset == before { stopMomentum() }   // parked at an edge
            return
        }
        guard let points = momentum.step(elapsed: elapsed) else { return stopMomentum() }
        scrollDebt += CGFloat(points)
        applyScrollDebt()
        // A local viewport already parked at the oldest line has nothing left
        // to reveal, and the debt would grow without bound — enough of it and
        // the flick back the other way would be swallowed doing nothing.
        let stuckAtTop = wasAtTop && points > 0 && gestureSink == .viewport
        if stuckAtTop { stopMomentum() }
    }

    private func stopMomentum() {
        momentumLink?.invalidate()
        momentumLink = nil
        momentum.stop()
        panMomentumX.stop()
        panMomentumY.stop()
        panActive = false
        scrollDebt = 0
        gestureSink = nil
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
        userScrollInFlight = true
        scrollTo(row: max(0, row - t.rows / 2))
        return row
    }

    var liveEdgeRow: Int { getTerminal().buffer.yDisp + getTerminal().rows }

    func setAltArmed(_ armed: Bool) {
        // Announce the state, don't just colour it: a sticky modifier whose
        // only signal is a background tint is invisible to VoiceOver, and to
        // any test that would catch it silently breaking. The colour itself
        // is the configurationUpdateHandler's job.
        altButton?.accessibilityValue = armed ? "armed" : nil
        altButton?.setNeedsUpdateConfiguration()
    }

    // SwiftTerm exposes inputAccessoryView as a settable var — assign, don't override.
    func installAccessoryBar() {
        inputAccessoryView = makeAccessory()
    }

    func setCtrlArmed(_ armed: Bool) {
        ctrlButton?.accessibilityValue = armed ? "armed" : nil
        ctrlButton?.setNeedsUpdateConfiguration()
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
            // Scheduled from main, so it fires on the main runloop. Asserting
            // that is what lets the timer touch main-isolated state honestly —
            // and it traps rather than racing if it ever stops being true.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.keyHandler?.accessoryKey(key, isRepeat: true) }
                }
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

        // Top hairline: the same light-catching edge the switcher's cards
        // wear, separating the bar from the terminal above it.
        let hairline = UIView()
        hairline.backgroundColor = UIColor(white: 1, alpha: 0.06)
        hairline.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hairline)
        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5)
        ])

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
            // 34pt is the budget, and it is SPENT: 40 and 38 were both tried
            // after ⌫'s removal freed width, and both push → off the first
            // screen (screenshot-checked) — the "spare" was already funding the
            // ⇞ peek that hints the bar scrolls. Fatter arrows would mean
            // thinner esc/tab/ctrl, which is the same miss rate moved around.
            ("←", .left, 34, "left arrow", nil),
            ("↓", .down, 34, "down arrow", nil),
            ("↑", .up, 34, "up arrow", nil),
            ("→", .right, 34, "right arrow", nil),
            // Past the fold: a TAP is redundant with the system delete, but a
            // HOLD is not — this is the only backspace that repeats.
            ("⌫", .backspace, 38, "backspace", nil),
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
            // The hairline every card in the app now wears; flat fills next
            // to the switcher's lit tiles read as an older generation of UI.
            cfg.background.strokeColor = UIColor(white: 1, alpha: 0.08)
            cfg.background.strokeWidth = 0.5
            cfg.contentInsets = .zero
            // Single glyphs (arrows, ⌫, paging) get two extra points: at 13pt
            // an arrowhead is a smudge, and unlike the word keys they have
            // width to spare.
            let capFont = UIFont.monospacedSystemFont(ofSize: label.count == 1 ? 15 : 13,
                                                      weight: .medium)
            cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var out = incoming
                out.font = capFont
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
            if key == .ctrl {
                ctrlButton = btn
                // Hold for the chord palette: tap still arms, hold offers the
                // combos a terminal actually reaches for. Labels say what the
                // chord DOES — "^R" alone assumes the muscle memory this
                // palette exists to replace.
                btn.menu = UIMenu(title: "Send control key", children: [
                    ("^C  interrupt", "c"), ("^R  search history", "r"),
                    ("^L  redraw", "l"), ("^Z  suspend", "z"),
                    ("^D  end input", "d"), ("^A  line start", "a"),
                    ("^E  line end", "e"), ("^K  cut to end", "k"),
                ].map { label, ch in
                    UIAction(title: label) { [weak self] _ in
                        self?.keyHandler?.accessoryKey(.ctrlCombo(Character(ch)))
                    }
                })
                btn.accessibilityHint = "Hold for control combos"
            }
            if key == .alt { altButton = btn }
            // One handler owns the cap's colour in every state, pressed and
            // armed both — the armed setters merely change accessibilityValue
            // (the contract the UI test already holds) and ask for an update.
            // Physical caps brighten under a finger; dimming reads as
            // disabled.
            btn.configurationUpdateHandler = { b in
                guard var c = b.configuration else { return }
                let armed = b.accessibilityValue == "armed"
                let base: UIColor = armed ? .hopKeyArmed : .hopKey
                c.background.backgroundColor = b.isHighlighted ? base.hopPressed : base
                c.baseForegroundColor = armed ? .black : .white
                b.configuration = c
            }
            stack.addArrangedSubview(btn)
        }
        return bar
    }
}

extension HopTermView: UIGestureRecognizerDelegate {
    /// Don't scroll out from under a selection: once one exists, dragging
    /// belongs to its handles. And a scroll is a VERTICAL gesture — anything
    /// mostly sideways belongs to whoever else wants it.
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if let pan = g as? UIPanGestureRecognizer {
            // The back swipe first: an edge pan IS a pan, so without this it
            // falls into the vertical-dominance rule below, which exists to
            // hand sideways drags to the swipe back — and was refusing the
            // very recognizer that performs it.
            if g is UIScreenEdgePanGestureRecognizer { return true }
            guard !selectionActive else { return false }
            // Panning a peer-sized grid is two-dimensional by nature; the
            // vertical-dominance rule below is for scrolling, where a sideways
            // drag belongs to the swipe back.
            if peerSizedGrid { return true }
            // A drag that grabs a coasting terminal keeps scrolling from
            // there, so pans are never braked — only started.
            let v = pan.velocity(in: self)
            return abs(v.y) >= abs(v.x)
        }
        if let tap = g as? UITapGestureRecognizer {
            // SwiftTerm's view is a SCROLL view, so location(in:) carries the
            // scrollback offset — a tap at the top of the screen reported y=461.
            // The strip means "the top of what you can SEE": bounds.origin.
            let inStrip = tap.location(in: self).y - bounds.origin.y < Self.chromeStrip
            if tap === chromeTap { return inStrip }
            if inStrip { return false }   // reaching for controls ≠ asking to type
        }
        // Everything else — tap, double tap, long press — is swallowed while
        // a coast is running, and stops it. Every scroll view on iOS works
        // this way: the first touch on something moving stops it and does
        // nothing else. Without this, stopping a coast also raises the
        // keyboard, shrinking the screen you were trying to read.
        if momentumLink != nil {
            Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                .info("coast braked by touch")
            stopMomentum()
            return false
        }
        return super.gestureRecognizerShouldBegin(g)
    }

    /// Coexist with the long-press and tap recognizers, which are how
    /// selection and focus still work — but NOT with the swipe back to the
    /// session list. Sharing that one means an edge swipe scrolls the terminal
    /// on its way out, and now that a flick coasts, it would go on sending
    /// wheel events to the agent after the screen is gone.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !(other is UIScreenEdgePanGestureRecognizer)
    }

    /// And when the two do overlap, the swipe back wins outright.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        other is UIScreenEdgePanGestureRecognizer
    }
}
