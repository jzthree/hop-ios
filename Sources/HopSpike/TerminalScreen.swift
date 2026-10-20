import SwiftUI
import SwiftTerm
import PhotosUI
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
    /// Shared with the app root: the terminal's light/dark is the whole
    /// app's appearance (Jian: "light UI to pair with the light terminal").
    @AppStorage("termLight") private var lightTheme = false
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
    /// User preference, off by default: the chrome persists unless you
    /// explicitly ask it to auto-hide (⋯ → Auto-hide menu). It used to
    /// auto-hide unconditionally 3s after open, which read as "I cannot
    /// invoke it easily" to anyone who didn't want that trade — now it's a
    /// trade you opt into, and the first time it actually hides under this
    /// setting, a one-time tip teaches the way back.
    @AppStorage("chromeAutoHide") private var chromeAutoHideEnabled = false
    /// Hold the screen lit while a terminal is open. Off by default: it is
    /// a battery trade, and one the user should make deliberately.
    @AppStorage("keepAwake") private var keepAwakeEnabled = false
    /// Arms the summon tip's anchor after the first auto-hide.
    @State private var chromeTipAnchor = false
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
    @State private var retryAt: Date?
    @State private var retryAttempt = 0
    @State private var retryGeneration = 0
    @State private var retryGraceArmed = -1
    @State private var bannerVisible = false
    @State private var renameShown = false
    @State private var renameText = ""
    @State private var taglineShown = false
    @State private var taglineText = ""
    @State private var killConfirmShown = false
    @State private var codexHandOffShown = false
    @State private var claudeHandOffShown = false
    /// The pill's live travel during a fleet-switch swipe. The web switcher
    /// has no equivalent of this: the pill follows the finger and names the
    /// session you would land on, so the swipe is never blind.
    @State private var pillDragX: CGFloat = 0
    /// Signed hop distance the current swipe would travel through the ring
    /// (negative = left/earlier, positive = right/next). Uncapped now — one
    /// drag can cross the whole ring (Jian); drives the lit card and the commit.
    @State private var swipeSteps: Int = 0
    /// Continuous horizontal scroll of the swipe filmstrip, in points — the
    /// strip tracks the finger so the ring slides under a fixed centre (current
    /// centred at rest). `swipeSteps` is this snapped to whole cards.
    @State private var swipeScrollX: CGFloat = 0
    /// One card slot: 78pt card + 8pt spacing. Shared by the drag→hops math and
    /// the filmstrip layout so the lit card lands dead centre.
    private let swipeCardW: CGFloat = 86
    /// An artifact link (hop view) being shown in-app.
    @State private var artifactViewing: ArtifactViewing?
    @State private var artifactURL: URL?
    /// What the ⋯ menu READS, frozen. Its rows show live session state (the
    /// Views count, the notify flag, who's here), and every session poll or
    /// presence blip re-rendered the open menu — SwiftUI's Menu re-lays out
    /// on a re-render, so it jumped under a finger mid-aim (Jian: "the menu
    /// moves itself, hard to tap"). Menu has no open/close hook to pause on,
    /// so the menu reads THIS copy instead, refreshed only on a slow cadence
    /// (the values change by the minute; a menu is open for seconds) and
    /// never mid-interaction. Slightly stale by design.
    @State private var menuSnap = MenuSnapshot()
    @State private var menuSnapAt = Date.distantPast
    struct MenuSnapshot: Equatable {
        var viewsCount: Int? = nil
        var notifyOnFinish = false
        var viewerNames: [String] = []   // names only: a typing flag flips every 1.2s
        var runningApp = ""              // the daemon's fg-process sample can flap between polls
    }
    private func refreshMenuSnapshot(force: Bool = false) {
        // 20s: long enough that a menu opened and used never sees a re-layout;
        // short enough that a stale count is gone by the next glance.
        guard force || Date().timeIntervalSince(menuSnapAt) > 20 else { return }
        let next = MenuSnapshot(
            viewsCount: liveSession.views?.count,
            notifyOnFinish: liveSession.notifyOnFinish,
            viewerNames: viewers.map(\.name),
            runningApp: liveSession.agentApp)
        if next != menuSnap { menuSnap = next }
        menuSnapAt = Date()
    }
    /// Attach a photo: the camera sheet, the system library picker, and the
    /// item it hands back (drained the moment it's read).
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var pillPeek: HopSession?
    @ObservedObject private var network = NetworkConditions.shared
    @State private var controlAction: ControlAction?
    @State private var toast: String?
    /// Where floating status UI (outage banner, "take mine") may start: just
    /// under the bar when it's shown (its measured height includes the
    /// island inset), else just under the island.
    /// The floating deliveries card (FloatingViewPreview): the session's
    /// recent `hop view` results, paged in a corner, until the reader closes
    /// it with ✕ (Jian: "always show it until the user explicitly closes it").
    @State private var floatIndex = 0
    @State private var floatTick = 0          // re-evaluate after seen-state changes
    /// Per session: the newest delivery time the reader CLOSED the card at.
    /// The card stays away until something newer than that lands.
    private static let floatClosedKey = "floatClosedAt"
    private static let floatMax = 12

    private var floatClosedAt: Double {
        ((UserDefaults.standard.dictionary(forKey: Self.floatClosedKey) as? [String: Double]) ?? [:])[session.internalName] ?? -1
    }
    private func setFloatClosedAt(_ t: Double) {
        var m = (UserDefaults.standard.dictionary(forKey: Self.floatClosedKey) as? [String: Double]) ?? [:]
        m[session.internalName] = t
        UserDefaults.standard.set(m, forKey: Self.floatClosedKey)
    }

    /// Recent file deliveries, newest first (live servers are not deliveries).
    private var floatDeliveries: [FloatingDelivery] {
        _ = floatTick
        return sessionViews
            .filter { !$0.isServer }
            .sorted { $0.mtime > $1.mtime }
            .prefix(Self.floatMax)
            .compactMap { item in
                URL(string: model.normalizedServerURL + item.path).map { FloatingDelivery(item: item, url: $0) }
            }
    }
    private var floatUnreadIDs: Set<String> {
        _ = floatTick
        return Set(floatDeliveries.filter { ViewSeen.itemState($0.item) != .seen }.map(\.id))
    }
    private var floatVisible: Bool {
        guard let newest = floatDeliveries.first, artifactViewing == nil else { return false }
        return newest.item.mtime > floatClosedAt
    }

    /// First sight of a session's deliveries: old results the reader has
    /// already seen (or that are hours old) shouldn't pop up on entry — only
    /// deliveries that are new to them. Recorded once, as if closed there.
    private func seedFloatBaseline() {
        guard floatClosedAt < 0, let newest = floatDeliveries.first else { return }
        let fresh = Date().timeIntervalSince1970 - newest.item.mtime < 30 * 60
        if !fresh || floatUnreadIDs.isEmpty { setFloatClosedAt(newest.item.mtime) }
        floatTick += 1
    }

    private func checkNewDelivery() {
        Task {
            await loadSessionViews()
            seedFloatBaseline()
            // A NEW delivery lands on page 1, so the card shows it.
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { floatIndex = 0; floatTick += 1 }
        }
    }

    private func openFloating(_ f: FloatingDelivery) {
        // The card stays (it is hidden only while the viewer covers it).
        if let i = sessionViews.firstIndex(where: { $0.path == f.item.path }) {
            artifactViewing = ArtifactViewing(items: sessionViews, index: i, serverURL: model.normalizedServerURL)
        } else {
            artifactViewing = ArtifactViewing(items: [f.item], index: 0, serverURL: model.normalizedServerURL)
        }
    }

    private var overlayTop: CGFloat {
        chromeShown && !landscapePhone && chromeHeightNow > 0 ? chromeHeightNow : windowTopInset()
    }
    /// One tap on the name reveals the WHOLE name (Jian: "the full screen
    /// session view often cannot display full session name — can one tap
    /// display the full name"). A pill-width title truncates anything past
    /// ~14 monospaced characters, and a tap there used to fall through to
    /// the bar background and HIDE the chrome — the opposite of "show me".
    @State private var fullNameShown = false
    @State private var checkbacksShown = false
    /// The Slack-style session drawer (SessionDrawer).
    @State private var drawerOpen = false
    /// Whether to hand the keyboard back when the drawer closes without a pick.
    @State private var keyboardUpBeforeDrawer = false

    @ViewBuilder private var drawerLayer: some View {
        if drawerOpen {
            SessionDrawer(currentInternal: session.internalName,
                          onPick: { name in
                              withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drawerOpen = false }
                              if name != session.internalName { model.requestedSession = name }
                          },
                          onAllSessions: { drawerOpen = false; dismiss() },
                          onClose: {
                              drawerMark("drawer close")
                              withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drawerOpen = false }
                              if keyboardUpBeforeDrawer {
                                  NotificationCenter.default.post(name: .hopRefocusTerminal, object: nil)
                              }
                          })
                .environmentObject(model)
                .transition(.move(edge: .leading))
                .zIndex(10)
                .onAppear { drawerMark("drawer appeared") }
        }
    }

    private func drawerMark(_ line: String) {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["HOP_SELECT_MARKER"],
              let h = FileHandle(forWritingAtPath: path) ?? {
                  FileManager.default.createFile(atPath: path, contents: nil); return FileHandle(forWritingAtPath: path) }()
        else { return }
        h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close()
        #endif
    }

    private func openDrawer() {
        // Two edge recognizers can both report one swipe.
        guard !drawerOpen else { return }
        drawerMark("drawer open (was \(drawerOpen)) in \(session.internalName)")
        // The keyboard would cover the bottom of the list. The terminal's
        // own resign: a nil-targeted resignFirstResponder left it up.
        keyboardUpBeforeDrawer = UIResponder.hopKeyboardShown
        NotificationCenter.default.post(name: .hopDropKeyboard, object: nil)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { drawerOpen = true }
    }
    /// Last bell-driven views refresh — the throttle for bellNudgesViews().
    @State private var lastBellRefresh = Date.distantPast
    @State private var viewers: [HayClient.Viewer] = []
    /// Presence minus this phone — what the company badge shows.
    @State private var otherViewers: [HayClient.Viewer] = []
    @State private var collabEveryone = true
    @State private var iHoldControl = false
    @State private var lockedByOther = false
    @State private var scrolledUp = false
    /// "76×24" while a peer/default size holds the grid — the size chip.
    @State private var peerSize: String?
    @State private var links: [String] = []
    @State private var showLinks = false
    /// Same dev hook the Account sheet uses: a panel that can only be reached
    /// by a gesture is a panel no screenshot check can see.
    /// The chrome overlay's rendered height, handed to the terminal so its
    /// "is this touch on the chrome" test tracks the expanded strip.
    @State private var chromeHeightNow: CGFloat = 0

    /// The Views list, expanded inline under the menu. Same dev hook as
    /// before so a screenshot can still reach it.
    @State private var viewsExpanded = {
#if DEBUG
        ProcessInfo.processInfo.environment["HOP_DEV_SHEET"] == "viewstrip"
#else
        false
#endif
    }()
    @State private var sessionViews: [ArtifactItem] = []
    /// Bumped after seen-marks that touch no other state, so the chip re-reads.
    @State private var viewsSeenTick = 0
    // Swipe-to-delete and tap arbitration now belong to the native List
    // (.swipeActions + .onTapGesture); the old hand-rolled DragGesture state
    // is gone with it — it was what broke scrolling on a long list.
    /// Renaming happens on the desktop too; without this the title here stays
    /// wrong until the next list refresh.
    @State private var renamedTitle: String?
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

    /// A bell in the live stream is `hop view`'s publish signal (among other
    /// things), so treat it as "the fleet summary just went stale": refresh
    /// the session list — which feeds the views chip's count and its unseen
    /// state — and the open strip if it's showing. Throttled, because agents
    /// can ring for reasons that arrive in bursts, and one refresh answers
    /// all of them.
    private func bellNudgesViews() {
        guard Date().timeIntervalSince(lastBellRefresh) > 2 else { return }
        lastBellRefresh = Date()
        Task {
            await model.refreshSessions(silent: true)
            if viewsExpanded { await loadSessionViews() }
        }
    }

    /// Split out of `body` for the same reason SessionsView is: the whole
    /// chain in one expression blows the SwiftUI type-checker's budget.
    /// The idle timer is APP-WIDE and sticky — set it once and the phone
    /// never sleeps again until someone puts it back. So everything that
    /// can take this screen away has to release it: leaving the screen,
    /// and the app backgrounding. iOS only honours it for the frontmost
    /// app anyway, which is precisely why hop can do this for a dictation
    /// and HopBoard cannot: the keyboard extension has no UIApplication,
    /// and during keyboard dictation hop is the app holding the screen.
    private func applyIdleTimer(_ awake: Bool? = nil) {
        UIApplication.shared.isIdleTimerDisabled = awake ?? keepAwakeEnabled
    }

    private var screen: some View {
        TerminalScreen(model: model, room: session.internalName, status: $status,
                       fontSize: fontSize, lightTheme: lightTheme,
                       fitWidth: fitWidth, autoScale: peerSize != nil, fitTick: fitTick,
                       chromeAutoHide: chromeAutoHideEnabled, landscape: landscapePhone,
                       chromeHeightNow: chromeShown && !landscapePhone ? chromeHeightNow : 0,
                       onSessionSwipe: { phase, dx in
                           // The drawer's swipe-to-close reaches the terminal's
                           // UIKit pans underneath; it must not ALSO switch
                           // sessions (closing the drawer landed you elsewhere).
                           if drawerOpen {
                               if phase != .moved { switchDragEnded(0, released: false) }
                               return
                           }
                           switch phase {
                           case .moved: switchDragMoved(dx)
                           case .commit: switchDragEnded(dx, released: true)
                           case .cancel: switchDragEnded(dx, released: false)
                           }
                       },
                       find: findRequest, reconnectToken: reconnectToken,
                       onToast: { toast = $0 },
                       onBell: { bellNudgesViews() },
                       onLinks: { found in
                           links = found
                           if found.isEmpty { toast = "No links on screen" } else { showLinks = true }
                       },
                       onFontChange: { setFont($0) },
                       onRenamed: { renamedTitle = $0 },
                       onGone: { goneReason = $0 },
                       onPresence: { viewers = $0 },
                       onOthers: { list in
                           withAnimation(.easeOut(duration: 0.2)) { otherViewers = list }
                       },
                       onCollab: { everyone, mine, other in
                           collabEveryone = everyone; iHoldControl = mine; lockedByOther = other
                       },
                       control: $controlAction,
                       onScroll: { scrolledUp = $0 },
                       onChromeTap: {
                           withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                               chromeShown.toggle()
                           }
                           // The lesson's completion: summoning donates the
                           // event, and the tip never shows again.
                           Task { await ChromeSummonTip.chromeSummoned.donate() }
                       },
                       onBodyTap: {
                           // Tapping the session below is the natural "done
                           // with the list" (Jian: "user should be able to
                           // collapse it by tapping elsewhere"). Logged: if a
                           // back tap ever routes here instead of the chevron,
                           // the diagnostics show this firing with the chevron
                           // silent — the signature of the expanded-strip back
                           // bug reaching the terminal's body-tap.
                           if viewsExpanded {
                               KBLog.record("bodyTap → collapse strip")
                               withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                   viewsExpanded = false
                               }
                           }
                       },
                       // Left-edge swipe opens the session drawer (Slack-
                       // style); the ‹ button in the bar is the way back.
                       onBackSwipe: { openDrawer() },
                       onOpenLink: { link in openLinkSmart(link) },
                       onFitRefresh: { fitTick += 1 },
                       onSizeState: { peerSize = $0 },
                       onRetryState: { at, attempt in
                           #if DEBUG
                           if let m = ProcessInfo.processInfo.environment["HOP_RETRY_MARKER"] {
                               let line = "retryState at=\(at.map { String(format: "%.1f", $0.timeIntervalSinceNow) } ?? "nil") attempt=\(attempt)\n"
                               let prev = (try? String(contentsOfFile: m, encoding: .utf8)) ?? ""
                               try? (prev + line).write(toFile: m, atomically: true, encoding: .utf8)
                           }
                           #endif
                           retryAttempt = attempt
                           guard let at else {
                               // Recovery: everything resets, banner drops.
                               retryAt = nil
                               bannerVisible = false
                               retryGeneration += 1
                               return
                           }
                           retryAt = at                    // countdown follows every cycle
                           // Grace measured from the OUTAGE'S START, not the
                           // last state change — retry cycles update state
                           // every second, and a per-update timer never
                           // matures (probe-caught: no outage length could
                           // show the banner). A blip that recovers inside
                           // the grace shows nothing at all.
                           if !bannerVisible, retryAt != nil, retryGeneration == retryGraceArmed {
                               // grace already armed for this outage
                           } else if retryGraceArmed != retryGeneration {
                               retryGraceArmed = retryGeneration
                               let gen = retryGeneration
                               Task { @MainActor in
                                   try? await Task.sleep(for: .milliseconds(1200))
                                   if gen == retryGeneration, retryAt != nil {
                                       bannerVisible = true
                                       #if DEBUG
                                       if let m = ProcessInfo.processInfo.environment["HOP_RETRY_MARKER"] {
                                           let prev = (try? String(contentsOfFile: m, encoding: .utf8)) ?? ""
                                           try? (prev + "bannerVisible\n").write(toFile: m, atomically: true, encoding: .utf8)
                                       }
                                       #endif
                                   }
                               }
                           }
                       })
    }

    // The drawer sits OUTSIDE the main chain: one more modifier there tipped
    // the type-checker over its time budget.
    var body: some View {
        mainBody.overlay { drawerLayer }
            .onReceive(NotificationCenter.default.publisher(for: .hopOpenDrawer)) { _ in openDrawer() }
    }

    private var mainCore: some View {
        screen
            .saturation(bannerVisible ? 0.55 : 1)
            .opacity(bannerVisible ? 0.82 : 1)
            .animation(.easeInOut(duration: 0.3), value: bannerVisible)
            .padding(.horizontal, 2)
            // Start the terminal BELOW the Dynamic Island, not under it (Jian:
            // "the top of the screen overlaps the island … start the terminal
            // from below the island and use the island space for other
            // purposes"). The old flat 40pt cleared the clock but not the
            // island — its safe-area top is ~59pt, so row zero of a
            // full-screen app (Claude's TUI, which can't scroll to shift
            // itself clear) sat under the notch. Reserve the real safe-area
            // top instead; the island band is the chrome's now. A 40pt floor
            // covers the pre-layout window where the inset reads 0, and older
            // non-notch phones where 40 is the friendlier clearance. The menu
            // band below the island is still cleared by chromeShift, not
            // reserved here, so toggling chrome never reflows the PTY.
            .padding(.top, max(40, windowTopInset()))
            // NO accessory padding: SwiftUI's keyboard avoidance already
            // clears the FULL keyboard frame INCLUDING the inputAccessoryView
            // riding on it, so the extra 46pt here was double-counted — a
            // dead band above the key bar exactly the bar's height (Jian:
            // "margin above the keyboard we can eliminate"; screenshot-
            // verified flush after removal, nothing hidden behind the bar).
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
                let dur: Double = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? -1
                KBLog.record("kbFrame endY=\(Int(end.origin.y)) h=\(Int(end.height)) screen=\(Int(screen)) up=\(up) dur=\(dur)")
                // Every keyboard-frame event schedules the settle check; the
                // check debounces itself, so only the burst's last survivor
                // runs.
                controlAction = .keyboardSettled
            }
            .alert("Rename session", isPresented: $renameShown) {
                TextField("name", text: $renameText).textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    Task { _ = await model.renameSession(session, to: renameText) }
                }
            }
            .alert("Edit tagline", isPresented: $taglineShown) {
                TextField("What is this session for?", text: $taglineText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task { _ = await model.setTagline(session, to: taglineText.trimmingCharacters(in: .whitespaces)) }
                }
            }
            .confirmationDialog("Kill \(session.name)?", isPresented: $killConfirmShown,
                                titleVisibility: .visible) {
                Button("Kill session", role: .destructive) {
                    Task {
                        if await model.killSession(session) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            // Codex lets one process write a thread: the app can only take
            // it over once this session's codex stops, so the hand-off is
            // Stop & park (resumable) plus opening the app on the Mac.
            .confirmationDialog("Hand \(session.name) to the Codex app?", isPresented: $codexHandOffShown,
                                titleVisibility: .visible) {
                Button("Stop here & open in Codex app") {
                    Task {
                        if await model.openInCodexApp(internalName: session.internalName, handOff: true) { dismiss() }
                    }
                }
                Button("Just show it in the app") {
                    Task { _ = await model.openInCodexApp(internalName: session.internalName, handOff: false) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Opens on the Mac. The app can continue the conversation only after it stops here; it's parked, and opening it in hop again picks it back up.")
            }
            // The Claude app adopts the CLI conversation in place, so claude
            // stops here first (one writer), exactly like the Codex hand-off.
            .confirmationDialog("Hand \(session.name) to the Claude app?", isPresented: $claudeHandOffShown,
                                titleVisibility: .visible) {
                Button("Stop here & open in Claude app") {
                    Task {
                        if await model.openInDesktopApp("claude", internalName: session.internalName, handOff: true) { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Opens on the Mac and continues there. It's parked here; opening it in hop again picks it back up.")
            }
            .confirmationDialog("Links on screen", isPresented: $showLinks, titleVisibility: .visible) {
                // Newest first, and capped: a build log can put dozens on
                // screen and an endless action sheet is unusable.
                ForEach(links.prefix(8), id: \.self) { link in
                    Button(displayLink(link)) { openLinkSmart(link) }
                }
                Button("Cancel", role: .cancel) {}
            }
            // The VIEWER is still a sheet — a PDF or a rendered page wants the
            // whole screen — but it takes first responder with it, and iOS
            // does not hand the keyboard back on dismiss. Jian hit exactly
            // that: "somehow keyboard got hidden after i interacted with the
            // views list." Restore focus ourselves when it closes.
            .fullScreenCover(item: $artifactViewing, onDismiss: {
                NotificationCenter.default.post(name: .hopRefocusTerminal, object: nil)
            }) { v in
                ArtifactSheet(viewing: v)
            }
            .fullScreenCover(item: $artifactURL, onDismiss: {
                NotificationCenter.default.post(name: .hopRefocusTerminal, object: nil)
            }) { url in
                ArtifactSheet(url: url)
            }
            // Attach a photo. The library is the system picker (no permission
            // prompt — it's sandboxed to what you choose); the camera needs
            // NSCameraUsageDescription and a real device.
            .photosPicker(isPresented: $showPhotoLibrary, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    let image = data.flatMap { UIImage(data: $0) }
                    await MainActor.run {
                        pickedPhoto = nil
                        attachPhoto(image)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                NotificationCenter.default.post(name: .hopRefocusTerminal, object: nil)
            }) {
                CameraPicker { image in
                    showCamera = false
                    attachPhoto(image)
                }
                .ignoresSafeArea()
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
                // The reconnect story, in words: a production app never
                // leaves a frozen screen unexplained. Shown whenever a
                // retry is pending or in flight; "Now" skips the backoff.
                if bannerVisible, let retryAt, goneReason == nil {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 12, weight: .semibold))
                        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                            let left = max(0, retryAt.timeIntervalSince(ctx.date))
                            Text(left > 0.5
                                 ? "Connection lost — retrying in \(Int(left.rounded()))s"
                                 : "Reconnecting…")
                                .font(.caption.weight(.medium)).monospacedDigit()
                        }
                        Button("Now") { reconnectToken += 1 }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.borderedProminent)
                            .tint(.hopPurple)
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hopAttention.opacity(0.5), lineWidth: 0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.top, overlayTop + (peerSize != nil ? 40 : 6))
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                }
                if let peerSize, goneReason == nil {
                    Button {
                        controlAction = .claimSize
                    } label: {
                        Label("\(peerSize) — take mine", systemImage: "arrow.down.right.and.arrow.up.left.rectangle")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.hopLine(0.10), lineWidth: 0.5))
                    }
                    .tint(.hopGlow)
                    // Under the bar's MEASURED bottom, never a fixed offset:
                    // the bar grew (it clears the island now) and a fixed
                    // +46 left the chip half-buried under it (probe
                    // screenshot 2026-10-01). Fixed size: its own type
                    // scale, nothing from the terminal's (remote) grid.
                    .padding(.top, overlayTop + 6)
                    .padding(.trailing, 8)
                    .fixedSize()
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
            // Recent `hop view` deliveries float in a corner, PiP-style,
            // until closed.
            .overlay {
                if floatVisible {
                    FloatingViewPreview(deliveries: floatDeliveries,
                                        unreadCount: floatUnreadIDs.count,
                                        unreadIDs: floatUnreadIDs,
                                        index: $floatIndex,
                                        topInset: overlayTop, bottomInset: 64,
                                        onOpen: { openFloating($0) },
                                        onClose: {
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                setFloatClosedAt(floatDeliveries.first?.item.mtime ?? Date().timeIntervalSince1970)
                                                floatTick += 1
                                            }
                                        })
                }
            }
            .onAppear { checkNewDelivery() }
            // Back from the viewer: seen-state changed under the card.
            .onChange(of: artifactViewing == nil) { _, closed in if closed { floatTick += 1 } }
            .onChange(of: liveSession.views?.latestAt) { _, _ in checkNewDelivery() }
            .overlay(alignment: .top) {
                if fullNameShown {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(renamedTitle ?? liveSession.name)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .textSelection(.enabled)
                        if !liveSession.tagline.isEmpty {
                            Text(liveSession.tagline)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.hopLine(0.10), lineWidth: 0.5))
                    .padding(.horizontal, 12)
                    .padding(.top, windowTopInset() + 52)   // just under the pill, like the outage banner
                    .transition(.opacity)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("full session name")
                    .onTapGesture { withAnimation { fullNameShown = false } }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation(.easeIn(duration: 0.2)) { fullNameShown = false }
                    }
                } else if let toast {
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
            .sheet(isPresented: $checkbacksShown) {
                CheckbacksSheet(session: liveSession).environmentObject(model)
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
    }

    // Second half of the chain (split for the type-checker).
    private var mainBody: some View {
        mainCore
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
                            .strokeBorder(Color.hopLine(0.08), lineWidth: 0.5))
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
                        Color.hopLine(0.06).frame(height: 0.5)
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
            .navigationBarBackButtonHidden(true)
            .statusBarHidden(landscapePhone)
            .overlay(alignment: .top) {
                // Suppressed once the session is gone (the ended card carries
                // its own way back), in landscape (every point is terminal),
                // and while FIND is open — both claim the top edge, and the
                // pill drew over the find bar (probe-caught: the field took
                // typing while the pill covered it).
                if chromeShown, !landscapePhone, !findOpen, goneReason == nil {
                    VStack(spacing: 0) {
                        chromeBar
                        // The list lives IN the chrome, not in a sheet
                        // (Jian). A sheet took first responder and the
                        // keyboard did not come back when it closed; it also
                        // covered the very session the result came from. The
                        // chrome is already an overlay that never touches the
                        // terminal's frame, so growing it downward costs no
                        // rows and no PTY resize — and dismissing it cannot
                        // lose the keyboard, because nothing ever took it.
                        if viewsExpanded { viewsStrip }
                    }
                    // SIZE only, never position (see the scar below): the
                    // overlay's height is stable through its own move-in
                    // transition, and the terminal needs it to know how much
                    // of its top is covered by chrome right now.
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { chromeHeightNow = g.size.height }
                            .onChange(of: g.size.height) { _, h in chromeHeightNow = h }
                    })
                    // NO self-measurement here, as a scar: a GeometryReader
                    // on this view once fed an offset meant to keep the bar
                    // out of the island's dead zone — but this view ENTERS by
                    // .move(edge: .top), so mid-transition it measured itself
                    // 437pt above the screen and the "compensation" parked
                    // the menu mid-screen (Jian: "the layout is broken, the
                    // menu is displayed in the middle or even the bottom").
                    // A view animating from off-screen cannot be its own
                    // position oracle. The island question is tracked from
                    // the STABLE UIKit measurement instead (KBLog "terminal
                    // shifted" lines in inChromeStrip).
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if chromeTipAnchor, !landscapePhone, goneReason == nil {
                    // An invisible anchor where the pill lives, carrying the
                    // one-time "tap here" lesson — only reachable when
                    // auto-hide actually fired (chromeTipAnchor), so someone
                    // who never enabled it never sees this either.
                    Color.clear
                        .frame(height: 1)
                        .popoverTip(ChromeSummonTip(), arrowEdge: .top)
                        .padding(.top, windowTopInset() + 8)
                }
            }
            // The swipe filmstrip: neighbours in the switch ring, current in
            // the middle, destination lit — so a sideways swipe shows what is
            // left and right and HOW MANY hops away, not just the next name
            // (Jian). Its own top overlay so it shows for the BODY swipe too,
            // when chrome is hidden.
            .overlay(alignment: .top) { swipeFilmstrip }
            .onChange(of: scenePhase) { _, phase in
                // iOS suspends the socket when the app backgrounds; coming back
                // to a dead terminal and having to hunt for a menu item was the
                // single most annoying part of using this on a phone.
                // Only a CLOSED socket needs this. Firing on .connecting too
                // meant becoming active while the first connect was still in
                // flight tore it down and started over — and every connect
                // pulls a fresh snapshot, up to 1.5 MB, on someone's cellular.
                // A swipe interrupted by the app suspending never delivers
                // its onEnded, and the peek title it left behind is a
                // PREVIEW of a session you never switched to. Jian, on
                // device: "room" came back from the background wearing
                // "lightscope"'s name — the ring's nearest neighbor, frozen
                // mid-drag. The peek dies with the foreground, both ways.
                if phase != .active {
                    pillPeek = nil
                    pillDragX = 0
                    swipeSteps = 0
                }
                if phase == .active, status == .closed { reconnectToken += 1 }
                if phase == .active, retryAt != nil { retryAt = Date() }   // wake: trying now
                // A LIVE-looking socket can be half-open after idle: the
                // screen paints, keystrokes vanish. Ping it on every wake;
                // a corpse feeds the normal reconnect machinery before the
                // user's first keystroke finds it (Jian: "the terminal
                // shows, but it doesn't take any user input"). The same
                // wake also RE-ESTABLISHES THE SIZE INVARIANT — a socket
                // that survived the idle used to get no size check at all,
                // which is the whole of "wrong size when I come back".
                if phase == .active, status == .live { controlAction = .wakeCheck }
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
                // Opening the session is reading its finished turn: the wall
                // tile goes quiet now, not on the next poll.
                model.markTurnSeen(session)
                // Chrome persists by default — no auto-hide. It used to vanish
                // 3s after open unconditionally, which traded a moment of
                // extra terminal rows for "I cannot invoke it easily" for
                // anyone who didn't want that trade; the same timer was ALSO
                // once misread by XCUITest as "menus don't open in an
                // overlay," costing hours on a test flake that wasn't one.
                // Auto-hide is opt-in now (⋯ → Auto-hide menu) — this task
                // only runs the timer for someone who asked for it.
                chromeShown = true
                guard chromeAutoHideEnabled else { return }
                guard !UIAccessibility.isVoiceOverRunning else { return }
                guard !ProcessInfo.processInfo.arguments.contains("-hop-ui-testing") else { return }
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { chromeShown = false }
                // First hide under this setting = the practice run. The tip
                // points at the summon strip and is dismissed by DOING it —
                // the summon donates the event, and the rule never shows it
                // again (see onChromeTap above).
                chromeTipAnchor = true
            }
            // Keep the session list live while you SIT in a terminal — and
            // with it the views chip's presence (0→1) and its unseen/yellow
            // state. The bell-nudge (onBell → bellNudgesViews) is immediate
            // but fragile: a `hop view` publish that raced the manifest
            // rebuild, or landed inside the 2s nudge throttle behind another
            // bell, left the chip dark until the next foreground — the "new
            // view doesn't light the button" report. A quiet heartbeat closes
            // that gap deterministically. Paused while backgrounded (the
            // socket is suspended anyway) and cancelled on leave (task id).
            .task(id: session.internalName) {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(6))
                    if Task.isCancelled { break }
                    guard scenePhase == .active else { continue }
                    await model.refreshSessions(silent: true)
                    if viewsExpanded { await loadSessionViews() }
                    // Throttled inside (20s): the poll is 6s, the menu must not be.
                    refreshMenuSnapshot()
                }
            }
            .onAppear {
                model.openSession = session.internalName
                model.markSeen(session)
                refreshMenuSnapshot(force: true)   // seed the menu's frozen view on entry
            }
            // Back from the viewer (which marks what you looked at): settle
            // the session-level mark and re-read the chip.
            .onChange(of: artifactViewing?.index) { _, idx in if idx == nil { reconcileViewsSeen() } }
            .onDisappear {
                // Guard the identity: switching sessions can appear-then-
                // disappear, and a blind clear would wipe the new one.
                if model.openSession == session.internalName { model.openSession = nil }
                applyIdleTimer(false)
            }
            .onAppear { applyIdleTimer() }
            .onChange(of: scenePhase) { _, phase in
                applyIdleTimer(phase == .active && keepAwakeEnabled)
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
    /// The session's results, hanging off the menu that summoned them.
    ///
    /// Deliberately not a List: this is chrome, a handful of rows, and a
    /// scroll view inside an overlay above a pannable terminal is a gesture
    /// fight nobody wins. Rows open the viewer; the strip stays put behind it
    /// so closing the viewer returns you here rather than to nothing.
    @ViewBuilder private var viewsStrip: some View {
        // BOUNDED and LAZY, whatever the list's size. The first version was a
        // plain VStack of every row: a session with a long publish history
        // built a screen-covering, gesture-laden layout inside the top
        // overlay — every touch below the bar landed on strip rows, nothing
        // could close it, and the session was unreachable (Jian: "when the
        // view list is too large... the UI becomes unresponsive"). The strip
        // now owns at most ~6 rows of height and scrolls within itself; the
        // bar above stays tappable by construction.
        Group {
            if sessionViews.isEmpty {
                Text("Nothing published yet — agents publish results with hop view.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // A native List, NOT a ScrollView of gesture-laden rows: the
                // old rows each carried a `DragGesture(minimumDistance: 0)`,
                // which claims the touch on contact and starved the ScrollView
                // of its vertical pan — so a long list could not scroll (Jian).
                // List scrolls natively AND gives swipe-to-delete via
                // `.swipeActions`, so nothing competes for the drag.
                let _ = viewsSeenTick
                if ViewSeen.anyUnseen(sessionViews) {
                    HStack {
                        Text("\(ViewSeen.unseenCount(sessionViews)) unseen")
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button { markAllViewsSeen() } label: {
                            Text("Mark all seen").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.hopAttention)
                        .accessibilityLabel("Mark all views seen")
                    }
                    .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
                }
                List {
                    ForEach(sessionViews) { item in
                        stripRow(item)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.hopPill)
                            .listRowSeparatorTint(Color.hopLine(0.06))
                            .contentShape(Rectangle())
                            .onTapGesture { openStripItem(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if !item.isServer {
                                    Button(role: .destructive) {
                                        Task { await stripDelete(item) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 44)
                .frame(height: min(CGFloat(sessionViews.count) * 52, 300))
                // The strip carries its OWN way out, at its bottom edge —
                // never occluded by the island, never dependent on the bar
                // above being tappable. Born from the day the bar went dead
                // and the list could scroll but not close.
                // Tap it, or DRAG it upward — a grab-handle that only taps
                // is a handle that lies about what it is (Jian: "…or drag
                // up the collapse button").
                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Close views")
                    .gesture(DragGesture(minimumDistance: 0)
                        .onEnded { v in
                            let dx = v.translation.width, dy = v.translation.height
                            let tapped = hypot(dx, dy) < 8
                            let draggedUp = dy < -20 && abs(dy) > abs(dx)
                            guard tapped || draggedUp else { return }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                viewsExpanded = false
                            }
                        })
            }
        }
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20,
                                   style: .continuous)
                .fill(Color.hopPill)
        )
        .overlay(
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20,
                                   style: .continuous)
                .strokeBorder(Color.hopLine(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
        // Load on APPEAR, not only on the tap that opened it: the strip can
        // also come up already expanded, and a list that renders "nothing
        // published yet" over five real results is worse than no list.
        .task { await loadSessionViews() }
    }

    /// One list row — pure content, NO gesture of its own (the List owns the
    /// scroll and the swipe-to-delete). A leading accent marks a view this
    /// device has not opened, or one republished newer since it last did.
    @ViewBuilder private func stripRow(_ item: ArtifactItem) -> some View {
        let state = item.isServer ? ViewSeen.ItemState.seen : ViewSeen.itemState(item)
        HStack(spacing: 10) {
            // Unread accent: solid for never-opened, glow for UPDATED-since;
            // clear (but space-holding) once seen, so rows stay aligned.
            Circle()
                .fill(state == .unseen ? Color.hopAttention
                      : state == .updated ? Color.hopGlow : Color.clear)
                .frame(width: 7, height: 7)
            Image(systemName: item.glyph)
                .font(.system(size: 13))
                .foregroundStyle(item.isServer
                                 ? (item.serverLive ? Color.hopAttention : Color.secondary)
                                 : Color.hopGlow)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.footnote.weight(state == .seen ? .medium : .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(stripSubtitle(item, state: state))
                    .font(.caption2)
                    .foregroundStyle(state == .updated ? Color.hopGlow : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hopPill)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(state == .seen ? "Opens. Swipe left to delete."
                           : "\(state == .updated ? "Updated" : "New"). Opens. Swipe left to delete.")
    }

    private func stripSubtitle(_ item: ArtifactItem, state: ViewSeen.ItemState) -> String {
        if item.isServer { return item.serverLive ? "live server" : "server gone" }
        let base = item.name.removingPercentEncoding ?? item.name
        return state == .updated ? "updated · \(base)" : base
    }

    /// Open a strip row's view — and mark it seen NOW, so its accent clears
    /// the moment you look (the body re-renders when the viewer presents and
    /// again when it dismisses, both re-reading the seen state).
    /// Take/pick → JPEG → host → path into the composer, with a toast at each
    /// end. The encode and upload run off the main actor; the paste lands on
    /// it. Nil (cancelled picker) is a quiet no-op.
    private func attachPhoto(_ image: UIImage?) {
        guard let image else { return }
        toast = "Uploading photo…"
        let internalName = session.internalName
        Task {
            guard let data = jpegForUpload(image) else {
                await MainActor.run { toast = "Couldn't read that photo" }
                return
            }
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let name = "photo-\(stamp).jpg"
            let r = await model.uploadFile(data, filename: name, session: internalName)
            await MainActor.run {
                if let path = r.path {
                    // Same quoting as the web's drop, plus a trailing space so
                    // the next thing typed doesn't glue onto the path.
                    NotificationCenter.default.post(name: .hopInsertText,
                                                    object: shellQuotePath(path) + " ")
                    toast = "Photo added — \(name)"
                } else {
                    toast = r.error ?? "Upload failed"
                }
            }
        }
    }

    private func markAllViewsSeen() {
        ViewSeen.markAllSeen(sessionViews)
        ViewSeen.markSeen(liveSession)
        viewsSeenTick += 1
    }

    /// After an item is seen: once none are left, the session-level mark
    /// (what the session list's chip reads) agrees.
    private func reconcileViewsSeen() {
        if !sessionViews.isEmpty, !ViewSeen.anyUnseen(sessionViews) { ViewSeen.markSeen(liveSession) }
        viewsSeenTick += 1
    }

    private func openStripItem(_ item: ArtifactItem) {
        ViewSeen.markItemSeen(item)
        reconcileViewsSeen()
        if let i = sessionViews.firstIndex(where: { $0.id == item.id }) {
            artifactViewing = ArtifactViewing(items: sessionViews, index: i,
                                              serverURL: model.normalizedServerURL)
        }
    }

    /// Dev hook, same family as HOP_DEV_SHEET: HOP_DEV_VIEWER=<index> opens
    /// the viewer on that row as soon as the strip's list lands, so a
    /// screenshot check can reach a surface that otherwise needs a tap.
    private func openViewerIfRequested() {
#if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["HOP_DEV_VIEWER"],
              let i = Int(raw), sessionViews.indices.contains(i), artifactViewing == nil else { return }
        artifactViewing = ArtifactViewing(items: sessionViews, index: i,
                                          serverURL: model.normalizedServerURL)
#endif
    }

    private func stripDelete(_ item: ArtifactItem) async {
        if await deleteArtifact(serverURL: model.normalizedServerURL,
                                urlSession: model.urlSession,
                                session: item.session, name: item.name) {
            withAnimation { sessionViews.removeAll { $0.id == item.id } }
            await model.refreshSessions(silent: true)
        }
    }

    /// Read the manifest for THIS session only. Cheap enough to re-read every
    /// time the strip opens, which is also how a result published while you
    /// were sitting here shows up without a reconnect.
    private func loadSessionViews() async {
        guard let url = URL(string: model.normalizedServerURL)?
            .appendingPathComponent("api/views") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["items"] as? [[String: Any]] else { return }
        sessionViews = raw.compactMap { o in
            guard let s = o["session"] as? String, s == session.internalName,
                  let n = o["name"] as? String, let p = o["path"] as? String else { return nil }
            let server = (o["kind"] as? String) == "server"
            let target = (o["target"] as? String) ?? ""
            return ArtifactItem(session: s, name: n, title: (o["title"] as? String) ?? "",
                                path: server && !target.isEmpty ? target : p,
                                isServer: server,
                                serverLive: (o["live"] as? Bool) ?? true,
                                bytes: (o["bytes"] as? Int) ?? 0,
                                mtime: (o["mtime"] as? Double) ?? 0)
        }
        openViewerIfRequested()
    }

    /// What this session has handed over that a terminal cannot draw.
    ///
    /// On the BAR, not buried in the menu: a result an agent published is the
    /// answer to the thing you asked for, and a surface you have to remember
    /// to go looking in is one you check after you needed it. Silent when the
    /// session has published nothing, so it costs nothing in the common case.
    ///
    /// A single tap goes straight to the newest result rather than to a list
    /// of one — that IS the deliverable most of the time. Long-press when you
    /// want the whole list.
    @ViewBuilder private var viewsChip: some View {
        if let v = liveSession.views {
            let _ = viewsSeenTick
            // Orange until EVERY item has been looked at (Jian: it went gray
            // "as long as I click on anything"): per-item state once the
            // list is loaded, the session summary before that. Opening the
            // strip marks nothing — looking at an item does.
            let unseen = sessionViews.isEmpty ? ViewSeen.isNew(liveSession)
                                              : ViewSeen.anyUnseen(sessionViews)
            Button {
                // Expands the menu it sits in rather than covering the
                // session. Always the list, even at one item: a chip that
                // sometimes opens a document and sometimes a list is a chip
                // you have to think about.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    viewsExpanded.toggle()
                }
                if viewsExpanded { Task { await loadSessionViews() } }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: unseen ? "sparkles.rectangle.stack.fill" : "rectangle.stack")
                        .font(.system(size: 12, weight: .semibold))
                    if v.count > 1 {
                        Text("\(v.count)").font(.caption2.weight(.semibold).monospacedDigit())
                    }
                }
                .foregroundStyle(unseen ? Color.hopPill : Color.primary)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(unseen ? Color.hopAttention : Color.hopLine(0.10),
                            in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hopLine(unseen ? 0 : 0.10),
                                                lineWidth: 0.5))
            }
            .accessibilityLabel(unseen
                ? "New result: \(v.latestLabel)"
                : "\(v.count) published view\(v.count == 1 ? "" : "s")")
            .contextMenu {
                Button {
                    // Same URL-as-string rule as the viewer: manifest
                    // paths are already paths, and appendingPathComponent
                    // would encode their slashes.
                    if let newest = sessionViews.filter({ !$0.isServer }).max(by: { $0.mtime < $1.mtime }) {
                        ViewSeen.markItemSeen(newest)
                        reconcileViewsSeen()
                    }
                    if let u = URL(string: model.normalizedServerURL + v.latestPath) {
                        artifactURL = u
                    }
                } label: { Label("Newest: \(v.latestLabel)", systemImage: "sparkles") }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        viewsExpanded = true
                    }
                    Task { await loadSessionViews() }
                } label: { Label("All views (\(v.count))", systemImage: "tray.full") }
                if unseen {
                    Button { markAllViewsSeen() } label: {
                        Label("Mark all as seen", systemImage: "checkmark.circle")
                    }
                }
            }
            .transition(.scale.combined(with: .opacity))
        }
    }

    /// The session as the LIST currently reports it, not the copy this screen
    /// was opened with. Views arrive while you are sitting in the terminal —
    /// reading the stale struct is why a freshly published result would not
    /// appear until you left and came back.
    private var liveSession: HopSession {
        model.sessions.first { $0.internalName == session.internalName } ?? session
    }

    private var chromeBar: some View {
        HStack(spacing: 8) {
            // The final shape, at Jian's word: TWO views — switcher and
            // terminal — one visible button between them, and no switch
            // menu in the title at all. The earlier duplication was the
            // button AND a menu; the resolution is the button WITHOUT the
            // menu, not the reverse (removing the button stranded him).
            Button {
                KBLog.record("back tapped viewsExpanded=\(viewsExpanded)")
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    // 72x50, the whole leading column of the pill: Apple's
                    // floor is 44pt and this is the single most-tapped control
                    // on the screen (Jian: "I often have to try several
                    // times", then "can still be hard to touch"). A near-miss
                    // used to fall through to the bar's background, whose tap
                    // HIDES the chrome — the bar vanished instead of going
                    // back, which reads as a dead button. Now every tap in
                    // this column is Back, and the background ignores it too.
                    .frame(width: 72, height: 50)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to sessions")
            // Mid-swipe the title becomes the DESTINATION: past the commit
            // threshold you read the name you will land on, not the one you
            // are leaving. Release inside the threshold and nothing happens.
            // The drag lives on the TITLE REGION (title + slack), not the
            // whole bar: with the gesture bar-wide, every slightly-moving
            // tap on the back chevron or the menu entered drag arbitration
            // first — the "have to try several times" bug. The body swipe
            // already covers the whole terminal, so the pill surface losing
            // its ends costs nothing.
            HStack(spacing: 0) {
                if let peek = pillPeek {
                    HStack(spacing: 7) {
                        Image(systemName: pillDragX < 0 ? "arrow.right" : "arrow.left")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.hopGlow)
                        Text(peek.name)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                } else {
                    titleLabel
                }
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
            // Tap = reveal the full name. Only text and glyphs live in this
            // region (no controls), so a tap gesture here enters no
            // arbitration; the 25pt drag and the long-press context menu
            // are untouched by a tap. Being in FRONT of the bar background,
            // it also stops a name tap from hiding the chrome.
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.18)) { fullNameShown = true }
            }
            .gesture(DragGesture(minimumDistance: 25)
                .onChanged { v in
                    let dx = v.translation.width
                    guard abs(dx) > abs(v.translation.height) * 2 else { return }
                    switchDragMoved(dx)
                }
                .onEnded { v in
                    // onChanged only fed horizontal-dominant drags, so a
                    // vertical one lit nothing and commits nothing.
                    switchDragEnded(v.translation.width, released: true)
                })
            viewsChip
            actionsMenu
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        // Content clears the island itself; the BACKGROUND (below) goes all
        // the way to y=0 — so what the island sits inside of and what the
        // controls sit inside of are the same uninterrupted black shape,
        // with no seam between "hardware black" and "app chrome" for the
        // island to visibly float above.
        .padding(.top, windowTopInset())
        // Square where it meets the screen edge (it's supposed to read as
        // the island's OWN blackness continuing down, not a separate rounded
        // panel starting near it); rounded at the bottom, where it resolves
        // into ordinary pill chrome holding the controls.
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0,
                                   style: .continuous)
                .fill(Color.hopPill)
                .ignoresSafeArea(edges: .top)
                // Tap-to-hide-chrome lives on the BACKGROUND, strictly behind
                // the controls, so the back chevron / chip / ⋯ always win the
                // touch. As a foreground `.onTapGesture` on the whole bar it
                // shared a subtree with those controls and entered gesture
                // arbitration with them — and with the views strip expanded,
                // that arbitration went the wrong way and the back tap was
                // eaten (Jian: "back button when hop view expanded still does
                // not work"). A background layer is never in that fight: empty
                // bar area falls through to it; a control in front consumes
                // its own touch first.
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { at in
                    // The Back column (leading 88pt) never hides the chrome:
                    // a tap that missed the chevron by a few points is a Back
                    // attempt, not a request to lose the bar.
                    guard at.x > 88 else {
                        KBLog.record("bar-bg tap in Back column ignored x=\(Int(at.x))")
                        return
                    }
                    KBLog.record("bar-bg tap → hide chrome (viewsExpanded=\(viewsExpanded))")
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { chromeShown = false }
                }
        )
        .overlay(
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 20,
                                   bottomTrailingRadius: 20, topTrailingRadius: 0,
                                   style: .continuous)
                .strokeBorder(Color.hopLine(0.06), lineWidth: 0.5)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.hopShadow, radius: 8, y: 2)
        // Safari's address-bar swipe, for terminals: drag the pill sideways
        // to step through the fleet in switcher order. Horizontal-dominant
        // and 50pt of travel, so bar taps and menu touches never misfire.
        // The pill FOLLOWS the finger (rubber-banded past the threshold) and
        // ticks once when the switch arms — the gesture used to be invisible
        // until it had already fired, which made it both undiscoverable and
        // blind about where it was going.
        .offset(x: pillDragX)
        .padding(.horizontal, 5)
        // No top padding here anymore — the background above already reaches
        // y=0 on its own (ignoresSafeArea); adding frame padding at this
        // level would just push the whole shape, background included, back
        // down and reopen the gap this exists to close.
    }

    /// ONE switch implementation for both surfaces — the pill drag and the
    /// terminal-body swipe land here, so thresholds, peek and haptics cannot
    /// drift apart. dx is horizontal finger travel; the peek pill arms past
    /// 50pt and the switch itself is the caller's commit verdict.
    private func switchDragMoved(_ dx: CGFloat) {
        let mag = abs(dx)
        let travel = mag <= 50 ? mag : 50 + (mag - 50) * 0.25
        pillDragX = (dx < 0 ? -1 : 1) * min(travel, 68)
        // Pure carousel: the filmstrip tracks the finger 1:1, so one drag can
        // cross the WHOLE ring, not a fixed ±2 (Jian). dx<0 (drag left) scrolls
        // FORWARD (+). A little rubber at the two ends — the strip does not
        // wrap, so running into blank space would lie about where you'd land.
        let ring = swipeRing(model.sessions, order: model.swipeOrder, scope: model.swipeScope,
                             including: session.internalName)
        guard ring.count > 1,
              let cur = ring.firstIndex(where: { $0.internalName == session.internalName }) else {
            if pillPeek == nil, swipeScrollX == 0 {
                KBLog.record("swipe: no ring (count=\(ring.count) scope=\(model.swipeScope) live=\(liveSession.live) createdBy=\(liveSession.createdBy))")
            }
            swipeScrollX = 0; swipeSteps = 0; pillPeek = nil; return
        }
        let maxForward = CGFloat(ring.count - 1 - cur) * swipeCardW
        let maxBack = CGFloat(cur) * swipeCardW
        var scroll = -dx
        if scroll > maxForward { scroll = maxForward + (scroll - maxForward) * 0.2 }
        else if scroll < -maxBack { scroll = -maxBack + (scroll + maxBack) * 0.2 }
        swipeScrollX = scroll
        let steps = max(-cur, min(ring.count - 1 - cur, Int((scroll / swipeCardW).rounded())))
        if steps != swipeSteps {
            swipeSteps = steps
            withAnimation(.easeOut(duration: 0.1)) { pillPeek = steps == 0 ? nil : ring[cur + steps] }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// WYSIWYG: releasing switches if and only if the filmstrip is lighting a
    /// different session — `pillPeek` IS `ring[cur + steps]`, nil at steps 0
    /// (Jian: "should trigger upon release as long as the purple highlighted
    /// session changed"). No distance or velocity gate: those could refuse a
    /// switch the user could SEE was armed, and the older flick rule did the
    /// opposite — jumping when nothing was lit. Direction is already settled
    /// upstream (both callers only feed horizontal-dominant drags).
    private func switchDragEnded(_ dx: CGFloat, released: Bool) {
        let landing = pillPeek
        withAnimation(.spring(duration: 0.3)) { pillDragX = 0; swipeScrollX = 0 }
        withAnimation(.easeOut(duration: 0.12)) { pillPeek = nil; swipeSteps = 0 }
        KBLog.record("swipe end dx=\(Int(dx)) released=\(released) lit=\(landing?.name ?? "nil")")
        guard swipeShouldCommit(lit: landing != nil, released: released),
              let next = landing else { return }
        model.requestedSession = next.internalName
    }

    /// The swipe filmstrip HUD: the ring slides under a fixed centre so the lit
    /// destination sits dead-centre and current is centred at rest — a sideways
    /// drag shows what is left and right and how far, across the whole ring
    /// (Jian). Its order is FROZEN (model.swipeOrder) so neighbours don't
    /// reshuffle mid-swipe. Non-interactive; the drag keeps the touch.
    @ViewBuilder private var swipeFilmstrip: some View {
        let ring = swipeRing(model.sessions, order: model.swipeOrder, scope: model.swipeScope,
                             including: session.internalName)
        if pillDragX != 0, ring.count > 1,
           let cur = ring.firstIndex(where: { $0.internalName == session.internalName }) {
            GeometryReader { geo in
                HStack(spacing: 8) {
                    ForEach(Array(ring.enumerated()), id: \.element.internalName) { pair in
                        let dist = pair.offset - cur
                        let isDest = dist == swipeSteps
                        VStack(spacing: 2) {
                            Text(pair.element.name)
                                .font(.system(.caption2, design: .monospaced)
                                        .weight(isDest ? .bold : .regular))
                                .lineLimit(1).truncationMode(.middle)
                            if dist == 0 {
                                Text("now").font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(isDest ? Color.hopPill : .secondary)
                            }
                        }
                        .frame(width: 78)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(
                            isDest ? Color.hopGlow : Color.hopLine(dist == 0 ? 0.16 : 0.06)))
                        .foregroundStyle(isDest ? Color.hopPill
                                         : (dist == 0 ? Color.primary : Color.secondary))
                        .scaleEffect(isDest ? 1.08 : 0.9)
                    }
                }
                .padding(.horizontal, 8)
                // Centre card `cur` at rest (8 lead pad + 39 half-card = 47),
                // then slide by the live scroll so the lit card lands centre.
                .offset(x: geo.size.width / 2 - (CGFloat(cur) * swipeCardW + 47) - swipeScrollX)
                .frame(height: 54, alignment: .leading)
                .animation(.easeOut(duration: 0.1), value: swipeSteps)
            }
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .background(Color.hopPill.opacity(0.55))
            // Fade the ends so cards scroll in and out of a window instead of
            // hard-clipping at the screen edge.
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.13),
                .init(color: .black, location: 0.87),
                .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .padding(.top, windowTopInset() + 50)
            .allowsHitTesting(false)
        }
    }

    /// One open path for every link, tapped or menu-picked: the user's own
    /// hop server (hop view artifacts) opens IN-APP with the session cookie —
    /// Safari has no hop session and would render the login page — and
    /// everything else goes to Safari.
    private func openLinkSmart(_ link: String) {
        guard let url = URL(string: link) else { return }
        if isOwnServerLink(link, serverURL: model.normalizedServerURL) {
            artifactURL = url
        } else {
            UIApplication.shared.open(url)
        }
    }

    /// A LABEL, not a menu. The in-title switcher is gone at Jian's word —
    /// switching happens in the switcher view (or the pill swipe, which
    /// stays: it is direct manipulation, not chrome). The dot, name, lock
    /// and viewer glyphs remain the terminal's one-line status.
    private var titleLabel: some View {
        HStack(spacing: 7) {
            // The readiness signal (Jian: "indicate clearly whether it is
            // ready for keyboard input without typing"): solid green is now
            // a VERIFIED claim — send failures and the wake ping both
            // demote a lying socket within a beat — and anything not-ready
            // breathes so the eye catches it without reading.
            Circle()
                .fill(status == .live ? Color.green : status == .connecting ? Color.yellow : Color.red)
                .frame(width: 8, height: 8)
                .sonar(when: status == .connecting, color: .yellow)
            Text(renamedTitle ?? liveSession.name)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .lineLimit(1)
            if lockedByOther {
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.orange)
            } else if !collabEveryone && iHoldControl {
                Image(systemName: "hand.raised.fill").font(.caption2).foregroundStyle(Color.hopGlow)
            }
            // Company, said out loud (Jian: "not showing the other user in
            // any obvious way"). A grey 2 next to a grey glyph read as
            // decoration; this is a filled badge that NAMES whoever else is
            // here, and turns amber the moment they type — the one fact that
            // changes what you should do next, since their keystrokes reflow
            // the grid you are reading.
            if !otherViewers.isEmpty {
                let others = otherViewers
                let typing = others.filter(\.typing)
                let label = others.count == 1
                    ? others[0].name
                    : "\(others.count) others"
                Label(typing.isEmpty ? label : "\(typing[0].name) typing…",
                      systemImage: typing.isEmpty ? "person.fill" : "keyboard.fill")
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(typing.isEmpty ? Color.hopGlow.opacity(0.20)
                                               : Color.hopAttention.opacity(0.28),
                                in: Capsule())
                    .foregroundStyle(typing.isEmpty ? Color.hopGlow : Color.hopAttention)
                    .transition(.opacity)
                    .accessibilityLabel(typing.isEmpty
                        ? "Also here: \(others.map(\.name).joined(separator: ", "))"
                        : "\(typing.map(\.name).joined(separator: ", ")) typing")
            }
            if !session.runningApp.isEmpty {
                Text(session.runningApp)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.hopPurple.opacity(0.22), in: Capsule())
                    .foregroundStyle(Color.hopGlow)
            }
        }
        // Long-press the NAME to act on the session — the native idiom is
        // pressing the object itself, and the name is the session's identity
        // in the pill. Same verbs as the ⋯ menu's Session group; two doors,
        // one @ViewBuilder.
        .contentShape(Rectangle())
        .contextMenu { TerminalActionsMenu.sessionVerbs(menuInputs, act: handleMenuAction) }
    }

    /// Everything the ⋯ menu's rows READ, as one Equatable value — the key
    /// `TerminalActionsMenu.==` compares to decide whether the menu may
    /// re-render at all. Add a field here the moment a row reads something
    /// new; a row reading the screen directly would silently bring the
    /// re-render-on-every-poll flicker back.
    private var menuInputs: TerminalActionsMenu.Inputs {
        #if DEBUG
        menuRenderLog.debug("screen body")   // once per screen re-render (see menu body)
        #endif
        return .init(live: status == .live,
              viewsCount: menuSnap.viewsCount,
              notifyOnFinish: menuSnap.notifyOnFinish,
              viewerNames: menuSnap.viewerNames,
              runningApp: menuSnap.runningApp,
              fitWidth: fitWidth,
              lightTheme: lightTheme,
              chromeAutoHide: chromeAutoHideEnabled,
              keepAwake: keepAwakeEnabled,
              collabEveryone: collabEveryone,
              iHoldControl: iHoldControl,
              folders: model.folders,
              folderId: liveSession.folderId,
              createdBy: liveSession.createdBy)
    }

    /// Everything a menu row DOES, in one place. Reads go through
    /// `liveSession`, never the `session` the screen was pushed with: the
    /// menu keeps the closure from the render that last changed its inputs,
    /// so anything captured by value in it can be minutes old. @State and
    /// @AppStorage writes are safe from a stale copy (they go to the shared
    /// storage, not the copy).
    private func handleMenuAction(_ action: TerminalActionsMenu.Action) {
        switch action {
        case .reconnect:
            reconnectToken += 1
        case .views:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                viewsExpanded = true
            }
            Task { await loadSessionViews() }
        case .toggleNotify:
            let want = !liveSession.notifyOnFinish
            Task {
                await model.setNotifyOnFinish(liveSession, on: want)
                refreshMenuSnapshot(force: true)   // your own toggle shows at once
            }
        case .checkbacks:
            checkbacksShown = true
        case .find:
            findOpen.toggle()
        case .copyScreen:
            NotificationCenter.default.post(name: .hopCopyScreen, object: nil)
        case .copyAll:
            NotificationCenter.default.post(name: .hopCopyAll, object: nil)
        case .takePhoto:
            if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            else { toast = "No camera on this device" }
        case .choosePhoto:
            showPhotoLibrary = true
        case .fork(let target):
            Task {
                if let fork = await model.forkSession(session.internalName, target: target) {
                    model.requestedSession = fork
                } else if let err = model.actionError { toast = err }
            }
        case .toggleFitWidth:
            fitWidth.toggle(); fitTick += 1
        case .fontStep(let delta):
            setFont(fontSize + Double(delta))
        case .toggleTheme:
            lightTheme.toggle()   // @AppStorage persists; the root re-schemes
        case .toggleAutoHide:
            chromeAutoHideEnabled.toggle()
            if !chromeAutoHideEnabled { chromeTipAnchor = false }
        case .toggleKeepAwake:
            keepAwakeEnabled.toggle()
            applyIdleTimer()
        case .control(let c):
            controlAction = c
        case .rename:
            renameText = liveSession.name; renameShown = true
        case .tagline:
            taglineText = liveSession.tagline; taglineShown = true
        case .moveToFolder(let id):
            Task { _ = await model.moveSession(session.internalName, toFolder: id) }
        case .toggleOrigin:
            Task {
                _ = await model.setOrigin(session.internalName,
                                          createdBy: liveSession.createdBy == "agent" ? "user" : "agent")
            }
        case .park:
            Task { if await model.setParked(liveSession, parked: true) { dismiss() } }
        case .kill:
            killConfirmShown = true
        case .codexApp:
            codexHandOffShown = true
        case .claudeApp:
            claudeHandOffShown = true
        }
    }

    /// `.equatable()` is the fix, not decoration — see `TerminalActionsMenu`.
    private var actionsMenu: some View {
        TerminalActionsMenu(inputs: menuInputs, act: handleMenuAction).equatable()
    }
}

/// The ⋯ menu as an EQUATABLE child of the screen. SwiftUI's Menu rebuilds
/// its UIKit menu whenever its content closure is re-evaluated, and the
/// screen's body re-evaluates on every AppModel publish (session polls, live
/// tile previews), status flip and presence blip — so an OPEN menu re-laid
/// itself out under the finger (Jian: "the menu moves itself"; then "still
/// flickering" after the values it SHOWS were snapshotted, because the
/// re-evaluation itself was the flicker, not the values). `.equatable()`
/// skips this view's body — and so the Menu — unless `inputs` changed.
/// The action closure is deliberately outside `==`: it's the door back to
/// the screen, not something a row shows.
///
/// Rule: nothing in here reads the screen. Rows read `inputs`; taps call
/// `act`. The screen owns the snapshot cadence for values that tick.
#if DEBUG
private let menuRenderLog = Logger(subsystem: "io.zhoulab.hop.spike", category: "menu-render")
#endif

struct TerminalActionsMenu: View, Equatable {
    struct Inputs: Equatable {
        var live: Bool
        var viewsCount: Int?
        var notifyOnFinish: Bool
        var viewerNames: [String]
        var runningApp: String
        var fitWidth: Bool
        var lightTheme: Bool
        var chromeAutoHide: Bool
        var keepAwake: Bool
        var collabEveryone: Bool
        var iHoldControl: Bool
        var folders: [HopFolder]
        var folderId: String?
        var createdBy: String
    }
    enum Action {
        case reconnect, views, toggleNotify, checkbacks
        case find, copyScreen, copyAll, takePhoto, choosePhoto
        case fork(target: String?)
        case toggleFitWidth, fontStep(Int), toggleTheme, toggleAutoHide, toggleKeepAwake
        case control(ControlAction)
        case rename, tagline, moveToFolder(String?), toggleOrigin, park, kill
        case codexApp
        case claudeApp
    }

    let inputs: Inputs
    let act: (Action) -> Void

    static func == (a: TerminalActionsMenu, b: TerminalActionsMenu) -> Bool { a.inputs == b.inputs }

    #if DEBUG
    /// Which input moved — every menu re-render is a potential re-layout
    /// under a finger, so each one should be explicable.
    nonisolated(unsafe) private static var lastInputs: Inputs?
    private static func logInputChange(_ i: Inputs) {
        defer { lastInputs = i }
        guard let p = lastInputs else { menuRenderLog.debug("menu inputs: first"); return }
        var changed: [String] = []
        if p.live != i.live { changed.append("live \(p.live)->\(i.live)") }
        if p.viewsCount != i.viewsCount { changed.append("viewsCount") }
        if p.notifyOnFinish != i.notifyOnFinish { changed.append("notify") }
        if p.viewerNames != i.viewerNames { changed.append("viewers \(p.viewerNames)->\(i.viewerNames)") }
        if p.runningApp != i.runningApp { changed.append("runningApp '\(p.runningApp)'->'\(i.runningApp)'") }
        if p.fitWidth != i.fitWidth { changed.append("fitWidth") }
        if p.lightTheme != i.lightTheme { changed.append("theme") }
        if p.chromeAutoHide != i.chromeAutoHide { changed.append("autoHide") }
        if p.keepAwake != i.keepAwake { changed.append("keepAwake") }
        if p.collabEveryone != i.collabEveryone { changed.append("collab \(p.collabEveryone)->\(i.collabEveryone)") }
        if p.iHoldControl != i.iHoldControl { changed.append("hold \(p.iHoldControl)->\(i.iHoldControl)") }
        if p.folders != i.folders { changed.append("folders") }
        if p.folderId != i.folderId { changed.append("folderId") }
        if p.createdBy != i.createdBy { changed.append("createdBy") }
        menuRenderLog.debug("menu inputs changed: \(changed.joined(separator: ", "), privacy: .public)")
    }
    #endif

    /// Fork (same tool) and the cross-tool handoffs, offered minus the tool
    /// this session is visibly running — the daemon decides what it REALLY
    /// runs (a restored session's process name can lie), and a wrong guess
    /// comes back as its error, surfaced like any other. Shared by the ⋯
    /// menu's Hand off submenu and the wall.
    @ViewBuilder static func forkVerbs(_ i: Inputs, act: @escaping (Action) -> Void) -> some View {
        Button { act(.fork(target: nil)) } label: {
            Label("Fork session", systemImage: "arrow.triangle.branch")
        }
        // Crossing tools: the conversation is extracted to a document the
        // new agent reads first (context handoff, not a resume — hop2
        // b81b17a). Same daemon call as the web sheet's "Continue in…".
        // runningApp is often empty for a claude session (the daemon sees
        // `zsh` in front), so the "fresh" label is best-effort; the daemon
        // knows what a session really runs and does the right handoff.
        if i.runningApp == "codex" {
            Button { act(.codexApp) } label: {
                Label("Hand off to Codex app…", systemImage: "macwindow")
            }
        }
        if i.runningApp == "claude" {
            Button { act(.claudeApp) } label: {
                Label("Hand off to Claude app…", systemImage: "macwindow")
            }
        }
        // Both, always: into the SAME tool it is a fresh session that reads
        // the condensed trajectory instead of the full, context-heavy
        // history (Jian: useful to "continue in claude from claude").
        Button { act(.fork(target: "codex")) } label: {
            Label(i.runningApp == "codex" ? "Continue in fresh Codex…" : "Continue in Codex…",
                  systemImage: "arrow.right.doc.on.clipboard")
        }
        Button { act(.fork(target: "claude")) } label: {
            Label(i.runningApp == "claude" ? "Continue in fresh Claude…" : "Continue in Claude…",
                  systemImage: "arrow.right.doc.on.clipboard")
        }
    }

    /// The session-identity verbs (the web sheet's), shared verbatim between
    /// the ⋯ menu's Session submenu and the title's long-press menu.
    @ViewBuilder static func sessionVerbs(_ i: Inputs, act: @escaping (Action) -> Void) -> some View {
        Button { act(.rename) } label: { Label("Rename", systemImage: "pencil") }
        Button { act(.tagline) } label: { Label("Edit tagline", systemImage: "text.quote") }
        Menu {
            ForEach(i.folders) { f in
                Button { act(.moveToFolder(f.id)) } label: {
                    if i.folderId == f.id {
                        Label(f.name, systemImage: "checkmark")
                    } else { Text(f.name) }
                }
            }
            if i.folderId != nil {
                Button { act(.moveToFolder(nil)) } label: { Label("Unfiled", systemImage: "tray") }
            }
        } label: { Label("Move to", systemImage: "folder") }
        Button { act(.toggleOrigin) } label: {
            Label(i.createdBy == "agent" ? "Move to You" : "Move to Agents",
                  systemImage: "arrow.left.arrow.right")
        }
        Button { act(.park) } label: { Label("Park", systemImage: "moon.zzz") }
        Button(role: .destructive) { act(.kill) } label: {
            Label("Kill", systemImage: "xmark.circle")
        }
    }

    /// The old menu was twelve items in arrival order — copy next to collab
    /// next to theme, one divider doing all the explaining. Regrouped by what
    /// an item acts ON, most-reached first: what this session has handed
    /// over / can be handed, the screen's content, then everything about
    /// HOW it's drawn folded under one More row.
    var body: some View {
        let i = inputs
        #if DEBUG
        // Measured 2026-09-26 (sim, live session, 45s): "screen body" +54,
        // "menu body" +1 — with .equatable() the menu no longer re-lays out
        // on the screen's ~1/s re-render. Re-measure with
        // `simctl spawn <sim> log stream --level debug --predicate 'category == "menu-render"'`.
        let _ = menuRenderLog.debug("menu body")
        let _ = Self.logInputChange(i)
        #endif
        Menu {
            // State-conditional, and FIRST: while the socket is verified
            // live a Reconnect row is dead weight — and it was the one row
            // that pushed the menu past the keyboard-up fold. During an
            // outage it leads the menu, because then it IS what you came for.
            if !i.live {
                Section {
                    Button { act(.reconnect) } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                }
            }
            Section {
                // The menu route to the same place the bar chip goes, for
                // when you want the list rather than the newest thing — and
                // the only route at all once the chip has been dismissed by
                // the chrome auto-hiding.
                Button { act(.views) } label: {
                    Label(i.viewsCount.map { "Views (\($0))" } ?? "Views",
                          systemImage: "rectangle.stack")
                }
                // Opt-in, per session: ring this phone when the agent finishes
                // a turn. Off by default (every-turn alerts across the fleet
                // would be noise); armed server-side so it holds on every
                // client, and the finish arrives as a bellSeq bump the existing
                // notifier surfaces.
                Button { act(.toggleNotify) } label: {
                    Label(i.notifyOnFinish ? "Stop notifying" : "Notify when finished",
                          systemImage: i.notifyOnFinish ? "bell.fill" : "bell")
                }
                // Have hop type something into this session later.
                Button { act(.checkbacks) } label: {
                    Label("Check back later…", systemImage: "alarm")
                }
            }
            Section {
                Button { act(.find) } label: { Label("Find", systemImage: "magnifyingglass") }
                Menu {
                    Button { act(.copyScreen) } label: {
                        Label("This screen", systemImage: "doc.on.doc")
                    }
                    Button { act(.copyAll) } label: {
                        Label("All scrollback", systemImage: "doc.on.clipboard")
                    }
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button { act(.control(.links)) } label: {
                    Label("Open link…", systemImage: "link")
                }
                // A photo is the one thing a phone can hand a session that a
                // desk can't. Take or pick; it lands on the host and its path
                // goes into the composer, so Claude reads it like any file.
                Menu {
                    Button { act(.takePhoto) } label: { Label("Take photo", systemImage: "camera") }
                    Button { act(.choosePhoto) } label: {
                        Label("Choose photo", systemImage: "photo.on.rectangle")
                    }
                } label: { Label("Add photo", systemImage: "camera.on.rectangle") }
            }
            // Fork / hand off from INSIDE the session — the moment you want
            // a copy, or the other tool, is usually mid-conversation.
            // Switches to the new session; the original keeps running.
            Section {
                Menu { Self.forkVerbs(i, act: act) } label: {
                    Label("Hand off", systemImage: "arrow.triangle.branch")
                }
            }
            // The rarely-reached tail — Display, Sharing, Session — folded
            // under ONE "More" row, so every top-level row is on screen at
            // once with the keyboard up (the first regroup left Sharing and
            // Session below a fold nothing hinted at; screenshot-caught).
            Section {
                Menu {
                    // Observer mode: see the peer's whole grid width at once
                    // instead of panning — and claim nothing while watching.
                    Button { act(.toggleFitWidth) } label: {
                        Label(i.fitWidth ? "Actual size" : "Fit to width",
                              systemImage: i.fitWidth
                                ? "arrow.up.left.and.arrow.down.right"
                                : "arrow.down.right.and.arrow.up.left")
                    }
                    // A stepper, not two one-shot rows: the menu stays up
                    // while you tap and the terminal re-fits live behind it.
                    // fontSize is NOT an input, so the taps re-fit the
                    // terminal without re-laying out this menu.
                    ControlGroup {
                        Button { act(.fontStep(-1)) } label: {
                            Label("Smaller text", systemImage: "textformat.size.smaller")
                        }
                        Button { act(.fontStep(1)) } label: {
                            Label("Bigger text", systemImage: "textformat.size.larger")
                        }
                    }
                    .menuActionDismissBehavior(.disabled)
                    Button { act(.toggleTheme) } label: {
                        Label(i.lightTheme ? "Dark mode" : "Light mode",
                              systemImage: i.lightTheme ? "moon.fill" : "sun.max.fill")
                    }
                    // Off by default: the menu persists until you ask for
                    // this trade. Turning it on arms the 3s timer in the
                    // session task; the first time it actually fires, a
                    // one-time tip teaches the way back (tap the top).
                    Button { act(.toggleAutoHide) } label: {
                        Label(i.chromeAutoHide ? "Keep menu visible" : "Auto-hide menu",
                              systemImage: i.chromeAutoHide ? "eye" : "eye.slash")
                    }
                    // A terminal is for WATCHING — an agent mid-turn, a
                    // build, a sentence you are still dictating — and the
                    // screen going dark interrupts all three. Only the
                    // frontmost app can ask for this, which is exactly why
                    // hop can and the HopBoard keyboard cannot.
                    Button { act(.toggleKeepAwake) } label: {
                        Label(i.keepAwake ? "Let the screen sleep" : "Keep screen awake",
                              systemImage: i.keepAwake ? "moon.zzz" : "sun.max")
                    }
                } label: { Label("Display", systemImage: "textformat.size") }
                Menu {
                    // Snapshot, not live presence (the screen freezes it):
                    // a viewer's typing flag flips every 1.2s.
                    ForEach(i.viewerNames, id: \.self) { name in
                        Label(name, systemImage: "person.fill")
                    }
                    Button { act(.control(i.collabEveryone ? .lock : .unlock)) } label: {
                        Label(i.collabEveryone ? "Lock typing to one user" : "Let everyone type",
                              systemImage: i.collabEveryone ? "lock" : "lock.open")
                    }
                    if !i.collabEveryone {
                        Button { act(.control(i.iHoldControl ? .release : .take)) } label: {
                            Label(i.iHoldControl ? "Release control" : "Take control",
                                  systemImage: i.iHoldControl ? "hand.raised.slash" : "hand.raised")
                        }
                    }
                } label: {
                    Label(i.viewerNames.count > 1
                            ? "Sharing — \(i.viewerNames.count) here" : "Sharing",
                          systemImage: "person.2")
                }
                // The web sheet's session verbs, reachable WITHOUT leaving
                // the terminal. Diagnostics lives here too: in the SESSION,
                // because the fault you want to report is usually on screen
                // right now — but rare, so not a top-level row.
                Menu {
                    Self.sessionVerbs(i, act: act)
                    Divider()
                    Button { act(.control(.sendDiagnostics)) } label: {
                        Label("Send diagnostics to hop", systemImage: "paperplane")
                    }
                } label: {
                    Label("Session", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            // Part of the pill, not a floating button: a hairline seam and a
            // bare glyph — the chevron's visual sibling at the other end
            // (Jian: the menu should feel integrated, not overlapping).
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.hopLine(0.10))
                    .frame(width: 0.5, height: 22)
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.hopPurple)
                    .frame(width: 38, height: 34)
            }
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

enum ControlAction { case take, release, lock, unlock, links, claimSize, keyboardSettled, wakeCheck, sendDiagnostics }

extension Notification.Name {
    static let hopCopyScreen = Notification.Name("hopCopyScreen")
    /// Posted when a sheet that stole first responder has closed. iOS does
    /// not restore the terminal's keyboard on its own, so the session came
    /// back unusable until you tapped it.
    static let hopRefocusTerminal = Notification.Name("hopRefocusTerminal")
    /// The session drawer opening: the keyboard would cover half of it.
    static let hopDropKeyboard = Notification.Name("hopDropKeyboard")
    /// A left-edge swipe anywhere in a session (relayed by BackSwipe).
    static let hopOpenDrawer = Notification.Name("hopOpenDrawer")
    /// The same swipe on the session list (no terminal pushed).
    static let hopOpenWallDrawer = Notification.Name("hopOpenWallDrawer")
    static let hopCopyAll = Notification.Name("hopCopyAll")
    /// Text handed to the terminal by the app (object: String) — an uploaded
    /// photo's path, pasted into the composer.
    static let hopInsertText = Notification.Name("hopInsertText")
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
    /// A peer holds the grid, so we render THEIR shape scaled to fit rather
    /// than drawing it at our font and letting it underfill or overflow.
    var autoScale = false
    /// Bumped when the room's elected size changes, so the fit font recomputes.
    var fitTick = 0
    /// Whether the menu is standing over the terminal's top rows right now —
    /// the terminal shifts its own content clear rather than losing the rows.
    var chromeAutoHide = false
    var landscape = false
    var chromeHeightNow: CGFloat = 0
    var onSessionSwipe: (HopTermView.SwipePhase, CGFloat) -> Void = { _, _ in }
    var find: FindRequest?
    var reconnectToken = 0
    var onToast: (String) -> Void = { _ in }
    var onBell: () -> Void = {}
    var onLinks: ([String]) -> Void = { _ in }
    var onFontChange: (Double) -> Void = { _ in }
    var onRenamed: (String) -> Void = { _ in }
    var onGone: (String) -> Void = { _ in }
    var onPresence: ([HayClient.Viewer]) -> Void = { _ in }
    var onOthers: ([HayClient.Viewer]) -> Void = { _ in }
    var onCollab: (Bool, Bool, Bool) -> Void = { _, _, _ in }
    @Binding var control: ControlAction?
    var onScroll: (Bool) -> Void = { _ in }
    var onChromeTap: () -> Void = {}
    /// Any approved single tap on the terminal BODY. The host uses it to
    /// dismiss transient chrome (the Views strip): tapping the session is
    /// the most natural "I'm done with the list" there is.
    var onBodyTap: () -> Void = {}
    var onBackSwipe: () -> Void = {}
    var onOpenLink: (String) -> Void = { _ in }
    var onFitRefresh: () -> Void = {}
    /// "76×24" while a peer/default size holds the grid, nil when the grid
    /// is ours — the size chip's feed. PLAN.md item 1: the re-entry size
    /// lottery becomes visible state with a one-tap exit.
    var onSizeState: (String?) -> Void = { _ in }
    /// (nextRetryAt, attempt) — nil when live. Feeds the reconnect banner.
    var onRetryState: (Date?, Int) -> Void = { _, _ in }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator(wsBase: model.wsBase, httpBase: model.normalizedServerURL, token: model.accessToken,
                    urlSession: model.urlSession, room: room, onToast: onToast, onLinks: onLinks,
                    onFontChange: onFontChange, onRenamed: onRenamed, onGone: onGone,
                    onPresence: onPresence, onCollab: onCollab, onScroll: onScroll,
                    onSizeState: onSizeState) { status = $0 }
        c.onRetryState = onRetryState
        c.onBodyTap = onBodyTap
        c.onOthers = onOthers
        c.onBell = onBell
        return c
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
        tv.onPossibleSizeMismatch = { [weak coordinator = context.coordinator] cols, rows in
            coordinator?.reassertOwnFit(cols: cols, rows: rows)
        }
        tv.onChromeTap = onChromeTap
        tv.onOpenLink = onOpenLink
        #if DEBUG
        if let scan = ProcessInfo.processInfo.environment["HOP_LINK_SCAN"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak tv] in tv?.debugScanLinks(to: scan) }
        }
        #endif
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
        tv.onSessionSwipe = onSessionSwipe
        context.coordinator.attach(view: tv)
        _ = tv.becomeFirstResponder()
        return tv
    }

    func updateUIView(_ uiView: HopTermView, context: Context) {
        _ = fitTick     // dependency: elected-size changes re-run this update
        // observeOnly stays the USER's explicit choice: it suppresses claims,
        // and a keystroke must still be able to claim while we are merely
        // auto-scaled. autoScale only changes how we DRAW.
        context.coordinator.observeOnly = fitWidth
        context.coordinator.autoScaling = autoScale
        if !fitWidth && !autoScale { context.coordinator.fitNudges = 0 }
        var size = CGFloat(fontSize)
        if fitWidth || autoScale {
            // The ELECTED columns, not the local terminal's. SwiftTerm re-fits
            // the terminal to the view on every layout pass, so by the time we
            // read it the peer's 100-column grid has already snapped back to
            // the phone's own ~47 — and scaling "to fit 47 columns" is a no-op
            // that leaves the daemon's 100-column output wrapping into a grid
            // that cannot hold it. That mismatch IS the half-height screen and
            // the mangled lines (probe-caught twice: identical rendering
            // before and after two other fixes).
            let elected = context.coordinator.electedCols
            let cols = (autoScale && elected > 1) ? elected : uiView.getTerminal().cols
            let width = uiView.bounds.width
            let advance = { (pt: CGFloat) -> CGFloat in
                HopTermView.cellSize(fontPt: pt, lineSpacing: uiView.lineSpacing).width
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
            // BOTH axes for auto-scale: a grid whose bottom rows sit below an
            // unscrollable viewport "fits" only in the dimension nobody was
            // complaining about — Jian: "it can say match while I cannot
            // scroll to bottom". The explicit Fit-to-width mode keeps its
            // name and stays width-only.
            let electedRows = context.coordinator.electedRows
            if autoScale, !fitWidth, electedRows > 1, uiView.bounds.height > 0 {
                let height = uiView.bounds.height
                let lineH = { (pt: CGFloat) -> CGFloat in
                    HopTermView.cellSize(fontPt: pt, lineSpacing: uiView.lineSpacing).height
                }
                for _ in 0..<3 {
                    let h = lineH(size) * CGFloat(electedRows)
                    if h <= height || size <= 4 { break }
                    size = max(4, size * height / h * 0.995)
                }
            }
            HopTermView.log.info("fit: cols=\(cols) width=\(Int(width)) -> \(size)pt")
        }
        // Only when it changed: setting a font re-lays-out the terminal, and
        // updateUIView runs on every SwiftUI pass — an unconditional set here
        // is a layout loop waiting for a trigger.
        if abs(uiView.font.pointSize - size) > 0.1 {
            uiView.font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            // A font change re-lays every cell, and SwiftTerm redraws only the
            // rows it believes changed — which is how a rescale left "one line
            // of text at the bottom messed up" (Jian). Mark the whole buffer
            // dirty so nothing stale can survive the pass.
            // Resync FIRST: the new font changed cellHeight under the
            // offset, and without this the full-screen repaint below would
            // repaint the wrong page for the settle's 400ms window.
            uiView.resyncViewport()
            uiView.getTerminal().updateFullScreen()
            uiView.setNeedsDisplay(uiView.bounds)
            uiView.applyLetterbox()
            uiView.scheduleSettleRedraw("font")
        }
        uiView.applyTheme(light: lightTheme)
        // What the menu is covering, in the terminal's own coordinates: the
        // strip it occupies, less the padding the terminal already starts
        // below. Zero whenever the menu isn't there to cover anything.
        uiView.chromeOverlap = (chromeAutoHide || landscape)
            ? 0 : max(0, HopTermView.chromeStrip - 40)
        uiView.chromeHeightNow = chromeHeightNow
        uiView.naturalFontPt = CGFloat(fontSize)
        uiView.runningAppName = model.sessions
            .first(where: { $0.internalName == room })?.runningApp ?? ""

        context.coordinator.themeIsLight = lightTheme
        context.coordinator.onBodyTap = onBodyTap
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
        uiView.stopFrameGapMonitor()
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate, AccessoryKeyHandler {
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
        /// The reconnect story, told honestly: (nextRetryAt, attempt) while a
        /// backoff is pending, nil once live again. Production apps don't
        /// leave a frozen screen wordless.
        var onRetryState: (Date?, Int) -> Void = { _, _ in }
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
        /// Drawing the peer's grid scaled to fit. Unlike observeOnly this does
        /// NOT suppress a keystroke's claim — it only changes how we draw.
        var autoScaling = false
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
        /// Consecutive foreign sizes refused while the user was looking. The
        /// circuit breaker on the refuse-and-re-assert rule: three, then we
        /// adopt and let the chip hand the decision to the human.

        /// THE gate on every outbound resize: is a human actually looking at
        /// this terminal right now? One PTY serves every client, so a resize
        /// this app sends reshapes whatever screen someone else is working
        /// in — that is a thing to do only on a live human's behalf, never
        /// because iOS re-laid-out a view in the background (the app-switcher
        /// snapshot is the loud one) or because a socket reconnected in a
        /// pocket. `.active` means foreground AND receiving events: during
        /// the app-switcher, Control Center, or a call banner it is
        /// `.inactive`, which is correctly NOT looking.
        var userIsLooking: Bool {
            UIApplication.shared.applicationState == .active
        }
        #if DEBUG
        /// One-shot latch for the wake-invariant probe hook.
        fileprivate var foreignSimDone = false
        #endif
        /// Local echo (the web's optimisticEcho, ported). Eligible only as
        /// the sole controller outside collab — multiple typists make echo
        /// reconciliation ambiguous, so the web never echoes there either.
        private var echo = OptimisticEcho()
        private var echoEligible = false

        /// A single TOUCH claims the size, not just typing. The web client
        /// reclaims on fit-on-type; a phone's first act on returning to a
        /// session is a TAP, and waiting for the first keystroke (or the 5s
        /// retry) left the foreign grid up exactly while the user was looking
        /// at it — Jian: "a single touch should trigger autofit". Called from
        /// the focusing tap, the click tap, and every delivered keystroke;
        /// throttled here so the callers don't need to care.
        func reclaimOnUserIntent() {
            guard isLive, !observeOnly, userIsLooking,
                  Date().timeIntervalSince(lastReclaimAt) > 1 else { return }
            // Force a layout pass BEFORE deciding anything: after a wake,
            // drawn/fitted dims can still describe the pre-lock layout, and
            // naturalFit() reads them — a stale read here is how a deliberate
            // claim locks in the WRONG size (sendAttachClaim forces layout
            // for the same reason).
            view?.setNeedsLayout()
            view?.layoutIfNeeded()
            guard fittedCols > 1, fittedRows > 1 else { return }
            // Two reasons a keystroke reclaims: a peer holds the grid (the
            // original case), OR the grid is nominally OURS but doesn't
            // match what this view actually fits — in EITHER direction.
            // Bigger than drawable was the pannable-not-scrollable bug;
            // smaller than the fit is its mirror, the half-height screen
            // (a keyboard-up grid surviving into a keyboard-down view).
            // Both used to be invisible to this guard: peerHoldsSize reads
            // false there, so typing was a no-op — reported verbatim, twice.
            let nat = view?.naturalFit()
            let grid = view?.getTerminal()
            let offNatural = !peerHoldsSize && nat != nil && grid != nil
                && (grid!.cols != nat!.cols || grid!.rows != nat!.rows)
            guard peerHoldsSize || offNatural else { return }
            view?.walkMark("reclaim peer=\(peerHoldsSize) offNatural=\(offNatural)")
            lastReclaimAt = Date()
            // A keystroke on THIS terminal is deliberate by definition —
            // carry the flag that wins outright. Claim the NATURAL fit: the
            // live fitted dims describe the auto-scaled font while a peer
            // holds the grid, and claiming those would take the peer's own
            // size — a keystroke that changes nothing.
            let claim = nat ?? (cols: fittedCols, rows: fittedRows)
            if offNatural {
                wakeMark("reclaim off-natural grid=\(grid!.cols)x\(grid!.rows) → \(claim.cols)x\(claim.rows)")
            }
            client.sendResize(cols: claim.cols, rows: claim.rows, user: true)
            #if DEBUG
            // The e2e probe's witness that intent reached the wire (the
            // pasteboard-style trap: the runner cannot see the socket).
            if let marker = ProcessInfo.processInfo.environment["HOP_CLAIM_MARKER"] {
                try? "\(fittedCols)x\(fittedRows)\n".write(toFile: marker,
                                                          atomically: true, encoding: .utf8)
            }
            #endif
        }

        /// Every keystroke goes through here: straight out on a live socket,
        /// buffered otherwise. A terminal's echo comes from the SERVER, so
        /// silence during an outage reads as a frozen app — hence the toast,
        /// throttled, since a burst of typing would be a burst of toasts.
        private func deliver(_ text: String) {
            guard !text.isEmpty else { return }
            if isLive {
                // Typing is how a size is reclaimed in hop: this keystroke
                // makes us the recent typist, so the claim rides along.
                // peerHoldsSize is NOT cleared on send — the server can
                // refuse, and only a CONFIRMED win (active_size matching our
                // fitted grid) clears it; clearing optimistically was measured
                // on device as "never autofits back no matter how much I
                // type". The throttle and the flag both live in the shared
                // intent path.
                // A keystroke means "show me the input box": the terminal
                // convention (scroll-on-input) and what SwiftTerm already does
                // for system-keyboard keys — its send(data:) path reveals the
                // caret, resetting the viewport to the live edge. Our history
                // anchor then dragged it BACK after the app's echo landed, so
                // every key showed the box, then the reading spot, then the box
                // (Jian, in Codex: "flickering between these two"). Two writers,
                // one policy now: the anchor yields to typing, and accessory-bar
                // keys (which bypass SwiftTerm's send) go to the edge as well.
                if let tv = view, let anchor = tv.historyAnchor {
                    tv.selectMark("typing: anchor=\(anchor) yDisp=\(tv.getTerminal().buffer.yDisp) → live edge")
                    tv.userScrollInFlight = true
                    tv.scrollTo(row: Int.max / 2)
                    tv.historyAnchor = nil
                    onScroll(false)
                }
                reclaimOnUserIntent()
                // Echo BEFORE the wire: the whole point is not waiting for
                // it. The original text goes to the daemon either way; only
                // printables render early, and reconcile eats the server's
                // copy when it returns.
                let echoed = echo.onInput(text, enabled: echoEligible)
                if !echoed.isEmpty { view?.feed(text: echoed) }
                client.sendInput(text)
                markTyping()
                armTypingProbe()   // catch a half-open socket that ate this keystroke
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
        /// When the server last sent ANYTHING back (output/snapshot/connect).
        /// A live socket echoes a keystroke within a beat, so silence past the
        /// probe window after typing means the socket is half-open — accepting
        /// writes into a black hole (`send` succeeds, nothing returns).
        private var lastInboundAt = Date.distantPast
        /// At most one liveness probe armed per window, so a burst of typing
        /// doesn't schedule a burst of checks.
        private var typingProbeScheduled = false

        /// Typed-but-no-answer watchdog. A half-open socket is invisible today:
        /// local echo paints the character and `send` reports success, so the
        /// dot stays green while nothing actually lands (Jian: "typing can
        /// remain unresponsive more than a few seconds without notifying"). If
        /// the server says nothing back within ~1.5s of a keystroke, ping it;
        /// verifyLiveness tears a dead socket down so the reconnect UI shows
        /// within ~2s. A false alarm (a keystroke that legitimately drew
        /// nothing) just costs one cheap pong and changes nothing.
        private func armTypingProbe() {
            guard !typingProbeScheduled else { return }
            typingProbeScheduled = true
            let sentAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.typingProbeScheduled = false
                guard self.isLive, self.lastInboundAt < sentAt else { return }
                self.client.verifyLiveness(timeout: 1.0)
            }
        }

        private func markTyping() {
            if !typingActive {
                typingActive = true
                client.sendTyping(true)
            }
            typingTimer?.invalidate()
            // Timers fire on the main run loop but their closure is typed
            // Sendable-nonisolated; assumeIsolated states the run-loop fact.
            typingTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.typingActive = false
                    self.client.sendTyping(false)
                }
            }
        }

        private func setStatus(_ state: TerminalHostView.ConnState) {
            isLive = state == .live
            pushStatus(state)
        }
        private let onToast: (String) -> Void
        private let onLinks: ([String]) -> Void
        private let onFontChange: (Double) -> Void
        var onBodyTap: () -> Void = {}
        private let onRenamed: (String) -> Void
        private let onGone: (String) -> Void
        private let onPresence: ([HayClient.Viewer]) -> Void
        private let onCollab: (Bool, Bool, Bool) -> Void
        private let onScroll: (Bool) -> Void
        /// Presence minus ourselves — set after construction, like
        /// onRetryState, to keep the init signature from growing again.
        var onOthers: ([HayClient.Viewer]) -> Void = { _ in }
        /// The BEL that just rang in this live stream, beyond the haptic.
        /// `hop view` rings it at the moment of publish, so this is the push
        /// signal that lets the views chip light NOW instead of whenever the
        /// next session poll happens to run. Set after construction, same
        /// pattern as onOthers.
        var onBell: () -> Void = {}
        private var ctrlArmed = false
        private var altArmed = false
        private var shiftArmed = false
        /// The last size we PUT ON THE WIRE, and when we last adopted a
        /// peer's — the two facts `shouldDeclareSize` needs to keep a size
        /// election from turning into a ping-pong.
        private var lastDeclared: (cols: Int, rows: Int, at: TimeInterval)?
        private var lastForeignAdoptAt: TimeInterval?
        private var declareWork: DispatchWorkItem?

        /// A non-claiming size message, COALESCED. The fit churns dozens of
        /// times through a keyboard settle; only the size it settles on is
        /// worth telling anyone about.
        func declareSize(_ cols: Int, _ rows: Int, reason: String) {
            declareWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let now = Date().timeIntervalSince1970
                guard shouldDeclareSize(cols: cols, rows: rows, now: now,
                                        lastSent: self.lastDeclared,
                                        lastForeignAdoptAt: self.lastForeignAdoptAt) else {
                    self.view?.walkMark("declare \(cols)x\(rows) SKIPPED (\(reason))")
                    return
                }
                self.lastDeclared = (cols, rows, now)
                self.view?.walkMark("declare \(cols)x\(rows) (\(reason))")
                self.client.sendResize(cols: cols, rows: rows)
            }
            declareWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
        }
        private var cmdArmed = false
        /// The hop keyboard's ⇧ and the bar's ⇧ are ONE armed state: either
        /// can arm it, both show it, and the next arrow consumes it.
        func setShiftArmed(_ on: Bool) {
            shiftArmed = on
            view?.setShiftArmed(on)
        }
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
            // The synchronous half of the keyboard-churn window (see
            // noteKeyboardChurn). Re-registering on a re-attach is harmless
            // only if the old registration goes first.
            NotificationCenter.default.removeObserver(
                self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.addObserver(
                self, selector: #selector(noteKeyboardChurn),
                name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            // Taps do NOT claim any more (Jian, revising his own rule:
            // "still only keystroke should"). A tap focuses and scrolls; it
            // is not a statement about whose screen this session belongs to.
            view.onUserIntent = { [weak self] in self?.onBodyTap() }
            client.onEvent = { [weak self] event in
                guard let self, let tv = self.view else { return }
                switch event {
                case .sendFailed(let text):
                    // The keystroke that discovered the corpse: into the
                    // replay buffer with every right to be replayed — the
                    // user typed it, the socket lied about being alive.
                    self.pending.append(text, at: Date())
                case .connected:
                    self.lastInboundAt = Date()
                    self.retryAttempt = 0      // healthy again: reset backoff
                    self.onRetryState(nil, 0)
                    self.echo.reset()
                    self.setStatus(.live)
                    self.claimSizeOnAttach()
                    self.replayPending()
                    self.startQuietWatch()
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
                    self.lastInboundAt = Date()   // the socket is answering — typing landed
                    if data.utf8.count > 32_768 {
                        KBLog.record("feed \(data.utf8.count / 1024)KB")
                    }
                    tv.noteRemoteModes(in: data)
                    tv.feed(text: self.echo.reconcileOutput(data))
                    // After the feed's display pass: SwiftTerm re-pins the
                    // offset on output, which would undo a pan while the desk
                    // is typing — and yank a scrolled-up reader back to the
                    // live edge in any session that prints steadily.
                    DispatchQueue.main.async { [weak tv, weak self] in
                        tv?.reapplyPan()
                        // The shift depends on how much history exists and
                        // where the cursor sits, and output moves both.
                        tv?.applyLetterbox()
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
                    self.lastInboundAt = Date()
                    self.echo.reset()          // the replay is the truth
                    self.wakeMark("snapshot fitted=\(self.fittedCols)x\(self.fittedRows)")
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
                    // Feed the replay at the PTY'S OWN grid, never at this
                    // screen's fit. A snapshot is bytes the PTY rendered for
                    // ITS size: every cursor address and repaint in it assumes
                    // that row count. Writing them into a terminal of a
                    // different height is how a Claude Code screen arrived as
                    // two overlapping pages ("the previous page was not
                    // completely cleaned"), and how a session came back at
                    // half height — one defect, two faces, and iOS-only
                    // because hop web never resizes on snapshot at all, it
                    // just writes (App.tsx case "snapshot").
                    //
                    // pinnedGrid is the SERVER's number: `joined` sets it from
                    // the PTY immediately before this snapshot, and every
                    // active_size re-sets it. fittedCols/Rows is a LOCAL
                    // measurement that goes stale whenever the keyboard state
                    // differs between the last layout pass and this replay —
                    // which is precisely why the ROWS drift while the columns
                    // (same font, same width, no keyboard on that axis) stay
                    // right (Jian: "the width is generally always fine, but
                    // the height is inconsistent").
                    if let g = replayGrid(pinned: tv.pinnedGrid,
                                          fitted: (self.fittedCols, self.fittedRows)) {
                        let t = tv.getTerminal()
                        if t.cols != g.cols || t.rows != g.rows {
                            self.wakeMark("snapshot regrid \(t.cols)x\(t.rows)→\(g.cols)x\(g.rows)"
                                + " (fit \(self.fittedCols)x\(self.fittedRows))")
                            self.view?.walkMark("local resize → \(g.cols)x\(g.rows)")
                            t.resize(cols: g.cols, rows: g.rows)
                        }
                    }
                    // Re-enter the modes the app is actually in. SwiftTerm keeps
                    // the buffer switch private, but a terminal takes modes as
                    // sequences, which is the honest way to say it anyway.
                    // Mouse reporting is deliberately NOT restored: on a touch
                    // screen a tap is how you reach the keyboard, and turning
                    // taps into clicks at the app is a behaviour change worth
                    // deciding on a device, not guessing at here.
                    // ?1049h alone is NOT enough: SwiftTerm "clears" the alt
                    // buffer on entry via fillViewportRows, which early-returns
                    // when lines exist — a real clear only happens on ?1049l
                    // EXIT, and resetToInitialState deliberately keeps the alt
                    // buffer (clearAlt: false). So after a wake, re-entering
                    // landed the replay on the PRE-SLEEP screen, and every
                    // cell the snapshot didn't repaint showed the old text
                    // (Jian: "text mixed up after coming back from
                    // background"; Europa trace, sizes all healthy). ED2+home
                    // scrubs the canvas the protocol's own way.
                    if alternateScreen { tv.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[H") }
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
                    tv.scheduleSettleRedraw("snapshot")
                case .presence(let list):
                    self.onPresence(list)
                    // Who is here BESIDES us. The badge needs this separately
                    // from the raw list, because the Sharing menu deliberately
                    // shows everyone including this phone.
                    self.onOthers(list.filter { $0.id != self.client.clientId })
                case .collab(let everyone, let controllerId):
                    let mine = controllerId != nil && controllerId == self.client.clientId
                    self.controlLocked = !everyone && !mine && controllerId != nil
                    // Same condition the web computes for optimisticActive.
                    let eligible = !everyone && mine
                    if self.echoEligible, !eligible { self.echo.reset() }
                    self.echoEligible = eligible
                    self.onCollab(everyone, mine, self.controlLocked)
                case .rejected(let reason):
                    self.onToast(reason)
                case .joined(let cols, let rows):
                    self.wakeMark("joined pty=\(cols)x\(rows)")
                    self.sizeAtJoin = (cols, rows)
                    // Pin to the PTY grid from the first byte, so the
                    // snapshot paints at the PTY's width and never at a
                    // local fit. The attach active_size right behind this
                    // re-pins with the owner verdict.
                    if cols > 1, rows > 1 { self.view?.pinnedGrid = (cols, rows) }
                case .renamed(let name):
                    self.onRenamed(name)
                case .serverError(let message):
                    self.onToast(message)
                    Logger(subsystem: "io.zhoulab.hop.spike", category: "protocol")
                        .error("server rejected a message: \(message, privacy: .public)")
                case .activeSize(let cols, let rows, let mine):
                    tv.walkMark("active_size \(cols)x\(rows) mine=\(mine) grid=\(tv.getTerminal().cols)x\(tv.getTerminal().rows)")
                    // One PTY, one size, and the server stamps every
                    // active_size with the OWNER's clientId — so "is this
                    // size ours" is an IDENTITY check, never a size
                    // comparison. (Comparing sizes is how this used to be
                    // fooled: once auto-scale engaged, the scaled fit
                    // matched the foreign grid by construction, every peer
                    // size confirmed as ours, and the chip and reclaim
                    // silently disarmed.)
                    //
                    // Ownership lives on the server now — the last user
                    // action (open or keystroke) owns the size, and a
                    // keystroke transfers ownership AND applies our declared
                    // fit before any resize of ours goes out. This client
                    // only renders the verdict.
                    self.electedCols = cols
                    self.electedRows = rows
                    if mine {
                        self.wakeMark("active_size \(cols)x\(rows) OURS")
                        self.peerHoldsSize = false
                        // Pin even when the grid is ours: a one-column local
                        // drift re-wraps every PTY row's tail onto the next
                        // row's start (the spill bug). The pin is the single
                        // source of truth for what is drawn; our refits go
                        // out as resizes and come back as the next elected
                        // size.
                        tv.pinnedGrid = (cols, rows)
                        let t = tv.getTerminal()
                        if t.cols != cols || t.rows != rows {
                            self.view?.walkMark("local resize → \(cols)x\(rows)")
                            t.resize(cols: cols, rows: rows)
                            t.updateFullScreen()
                            tv.setNeedsDisplay(tv.bounds)
                            tv.applyLetterbox()
                            tv.scheduleSettleRedraw("resize-ours")
                            self.onGridChange()
                        }
                        self.onSizeState(nil)
                        self.stopReclaimRetry()
                    } else if tv.getTerminal().cols != cols || tv.getTerminal().rows != rows {
                        // Adopt IMMEDIATELY. The old 1.2s deferral painted
                        // the snapshot at the stale width and then rewrapped
                        // the whole just-painted transcript — the first
                        // controlled repro of the corruption.
                        self.wakeMark("active_size \(cols)x\(rows) ADOPT-FOREIGN")
                        // Answering an adopt immediately IS the ping-pong.
                        self.lastForeignAdoptAt = Date().timeIntervalSince1970
                        self.adoptForeign(cols: cols, rows: rows)
                    } else {
                        // Grid already drawn at the peer's size — a refused
                        // declaration's rebroadcast. Keep the chip up; the
                        // next keystroke takes the size back server-side.
                        self.peerHoldsSize = true
                        tv.pinnedGrid = (cols, rows)
                        self.onSizeState("\(cols)×\(rows)")
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
                    self.onGone(message)   // the gone screen says it; the buffer stays clean
                case .failed(let reason, let permanent):
                    // After a known end, the socket closing is a consequence,
                    // not news. Saying "connection lost" under "session
                    // terminated" reads as a second, unrelated problem.
                    if self.sessionEnded { return }
                    self.setStatus(.closed)
                    // NO text into the terminal (Jian, on device: "two lines
                    // of red text" flashing on every lock/unlock — and living
                    // in the scrollback forever). Permanent failures get the
                    // gone screen with the reason; transient ones get the
                    // banner, and only if they outlast the grace period.
                    if permanent { self.onGone(reason) }
                    if !permanent { self.scheduleRetry() }
                case .closed:
                    if self.sessionEnded { return }
                    self.echo.reset()
                    self.setStatus(.closed)
                    self.scheduleRetry()
                }
            }
            NotificationCenter.default.addObserver(self, selector: #selector(copyScreen),
                                                   name: .hopCopyScreen, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(copyAll),
                                                   name: .hopCopyAll, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(jumpToLive),
                                                   name: .hopJumpToLive, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(refocusTerminal),
                                                   name: .hopRefocusTerminal, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(dropKeyboard),
                                                   name: .hopDropKeyboard, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(insertText(_:)),
                                                   name: .hopInsertText, object: nil)
            #if DEBUG
            // Wake-invariant probe: HOP_DEV_FOREIGN_SIZE=100x30 makes the
            // first BACKGROUNDING adopt that grid — exactly what the daemon's
            // active_size broadcast does to a phone that isn't active (the
            // deferred-adopt grace requires .active). Simulating the desk
            // resizing the PTY while the phone sleeps is the only way to test
            // the wake path hermetically; the alternative is choreographing a
            // second WS client mid-test.
            // The app-switcher snapshot, simulated: iOS re-lays-out this view
            // on the way to the background, at a size that is not the user's.
            // HOP_DEV_BG_REFIT=1 reproduces that squeeze so the "never resize
            // while nobody is looking" rule has something real to be tested
            // against — a plain simctl home-press changes no bounds at all,
            // and a test that cannot fail proves nothing.
            if ProcessInfo.processInfo.environment["HOP_DEV_BG_REFIT"] == "1" {
                NotificationCenter.default.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil, queue: .main) { [weak view] _ in
                        MainActor.assumeIsolated {
                            guard let v = view else { return }
                            var f = v.frame
                            f.size.height *= 0.7
                            v.frame = f
                            v.setNeedsLayout()
                            v.layoutIfNeeded()
                        }
                    }
            }
            if let spec = ProcessInfo.processInfo.environment["HOP_DEV_FOREIGN_SIZE"] {
                NotificationCenter.default.addObserver(
                    forName: UIApplication.didEnterBackgroundNotification,
                    object: nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self, !self.foreignSimDone else { return }
                            let parts = spec.split(separator: "x").compactMap { Int($0) }
                            guard parts.count == 2 else { return }
                            self.foreignSimDone = true
                            self.adoptForeign(cols: parts[0], rows: parts[1])
                        }
                    }
            }
            #endif
            view.startFrameGapMonitor()
            snapshotLanded = false
            claimed = false
            connectStartedAt = Date()
            wakeEpochReset("attach")
            fastPaint(room: room)
            // A row from a LIVE list attaches immediately, as always. A row
            // the wall only knows from the launch CACHE is hearsay — and
            // attaching to a killed-but-remembered name makes the daemon
            // resurrect it (probe-proven: the gone-test's tap brought
            // GoneProbe back from the dead). Verify hearsay first.
            if AppModel.shared.liveListSeen {
                let t = view.getTerminal()
                let announce = announceSize(t)
                client.connect(base: wsBase, httpBase: httpBase, room: room,
                               cols: announce.cols, rows: announce.rows,
                               token: token, using: urlSession,
                               sizeClaim: !observeOnly && userIsLooking && canClaimAtConnect())
            } else {
                verifyThenConnect()
            }
        }

        /// The reconnect path's existence check, shared with cache-hearsay
        /// attaches: refresh, refuse if the room is provably gone, connect
        /// otherwise (no evidence → proceed; refusing on none would be
        /// worse than the bug).
        private func verifyThenConnect() {
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
                let announce = self.announceSize(t)
                self.client.connect(base: self.wsBase, httpBase: self.httpBase, room: self.room,
                                    cols: announce.cols, rows: announce.rows,
                                    token: self.token_, using: self.urlSession,
                               sizeClaim: !observeOnly && userIsLooking && canClaimAtConnect())
            }
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
            case .keyboardSettled:
                scheduleKeyboardSettleCheck()
            case .sendDiagnostics:
                sendSessionDiagnostics()
            case .wakeCheck:
                runWakeCheck()
            case .claimSize:
                // The chip's tap: ask for our fitted size. The election may
                // refuse (someone typed recently) — the refusal rebroadcast
                // re-arms the chip, which is the honest answer.
                if let claim = view?.naturalFit() ?? (fittedCols > 1 && fittedRows > 1
                                                      ? (cols: fittedCols, rows: fittedRows) : nil) {
                    client.sendResize(cols: claim.cols, rows: claim.rows, user: true, take: true)
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
                // A screen at a FOREIGN size we are about to claim away from
                // is not worth painting: it would show for ~200ms and then
                // reflow — the exact size-change Jian sees on open. Skip it;
                // the snapshot (at our size, with the connect-time claim)
                // is the first frame.
                if !self.observeOnly, self.userIsLooking, let fit = tv.naturalFit(), fit.cols > 1,
                   let c = jsonInt(obj["cols"]), let r = jsonInt(obj["rows"]),
                   c != fit.cols || r != fit.rows {
                    self.wakeMark("fastPaint skipped: \(c)x\(r) ≠ fit \(fit.cols)x\(fit.rows)")
                    return
                }
                if let cols = jsonInt(obj["cols"]), let rows = jsonInt(obj["rows"]),
                   cols > 1, rows > 1, t.cols != cols || t.rows != rows {
                    self.view?.walkMark("local resize → \(cols)x\(rows)")
                    t.resize(cols: cols, rows: rows)
                }
                self.wakeMark("fastPaint grid=\(t.cols)x\(t.rows) fitted=\(self.fittedCols)x\(self.fittedRows)")
                tv.feed(text: screen)
                tv.scheduleSettleRedraw("fastPaint")
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
            // The SAME padded rows tapping uses, so the list and the tap
            // agree about what is a link (the wrap flag alone missed every
            // URL an app broke itself — inside a box rule, under a bullet).
            var rows: [String] = []
            rows.reserveCapacity(t.rows)
            for row in 0..<t.rows {
                var line = t.getLine(row: row + t.buffer.yDisp)?
                    .translateToString(trimRight: true) ?? ""
                if line.count > t.cols { line = String(line.prefix(t.cols)) }
                rows.append(line.padding(toLength: t.cols, withPad: " ", startingAt: 0))
            }
            return linksIn(rows: rows)
        }

        func detach() {
            alive = false
            quietWatch?.cancel()
            quietWatch = nil
            stopReclaimRetry()
            typingTimer?.invalidate()
            if typingActive { client.sendTyping(false) }
            retryTask?.cancel()
            NotificationCenter.default.removeObserver(self)
            client.close()
        }

        /// Quiet-socket watchdog. A socket can die half-open while you SIT
        /// in a session — the Mac sleeps or loses its network, the tunnel
        /// drops — and nothing on this side notices: no receive fails, no
        /// send fails, the dot stays green and the screen just stops. The
        /// wake ping only runs on a return to the foreground and the typing
        /// probe only after a keystroke, so a session you were reading
        /// stayed frozen until you backed out to the list and reopened it
        /// (Jian, alphagenome, 10/19 — the Mac's network was down
        /// 23:40–23:52 UTC). Every 10s while foreground and live: if the
        /// server has said nothing for 15s, ping it; no pong → the normal
        /// reconnect machinery. A pong costs a few bytes and changes nothing.
        private var quietWatch: Task<Void, Never>?
        private func startQuietWatch() {
            guard quietWatch == nil else { return }
            quietWatch = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard let self, self.alive else { return }
                    guard self.isLive, !self.sessionEnded,
                          UIApplication.shared.applicationState == .active,
                          Date().timeIntervalSince(self.lastInboundAt) > 15 else { continue }
                    self.client.verifyLiveness(timeout: 5)
                }
            }
        }

        /// Reconnect on our own — IMMEDIATELY the first time (0s, 1s, 2s,
        /// 4s, 8s, capped at 15s from there). Most disconnects are a tunnel
        /// blip or a phone waking from sleep and are already gone by the
        /// time a socket would even finish waiting to check — Jian: "most
        /// disconnect can be fixed immediately." Backing off only starts
        /// once that immediate retry has already failed, so a genuinely
        /// dead server still doesn't get hammered.
        private func scheduleRetry() {
            guard alive, !sessionEnded, retryTask == nil else { return }
            let delay = retryAttempt == 0 ? 0.0 : min(15.0, pow(2.0, Double(retryAttempt - 1)))
            retryAttempt += 1
            onRetryState(Date().addingTimeInterval(delay), retryAttempt)
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self, self.alive, !Task.isCancelled else { return }
                await MainActor.run {
                    self.retryTask = nil
                    guard let tv = self.view else { return }
                    self.setStatus(.connecting)
                    self.onRetryState(Date(), self.retryAttempt)   // "now": trying
                    // The automatic retry is the MOST common reconnect — a
                    // tunnel blip, or a phone waking up — and it was the one
                    // path that never fast-painted, so the case where you're
                    // already staring at a dead terminal was the slowest.
                    self.snapshotLanded = false
                    self.claimed = false
                    self.connectStartedAt = Date()
                    self.wakeEpochReset("retry-reconnect")
                    self.fastPaint(room: self.room)
                    // Through announceSize like every other connect path: a
                    // pocket auto-retry must announce the ELECTED size, not
                    // whatever grid the local terminal happens to hold (a
                    // stale adopted foreign grid reshaped sessions from a
                    // pocket here).
                    let announce = self.announceSize(tv.getTerminal())
                    self.client.connect(base: self.wsBase, httpBase: self.httpBase, room: self.room,
                                        cols: announce.cols, rows: announce.rows,
                                        token: self.token_, using: self.urlSession,
                               sizeClaim: !observeOnly && userIsLooking && canClaimAtConnect())
                }
            }
        }


        /// The dimensions to ANNOUNCE on a WS connect.
        ///
        /// Every attach carries cols/rows in the URL, and the daemon records
        /// them for the size election — so a reconnect that happens while the
        /// phone is in a pocket (network change, brief resume) announces the
        /// phone's shape into a session someone else is working in. That is
        /// the last way this app could still reshape a terminal with nobody
        /// looking at it (Jian: "should stop stealing focus (refit) while in
        /// the background"). While inactive we announce the size we last knew
        /// the ROOM to be, which proposes nothing new; our own fit is claimed
        /// on the first keystroke, as everything else now is.
        private func announceSize(_ t: Terminal) -> (cols: Int, rows: Int) {
            if !userIsLooking, electedCols > 1, electedRows > 1 {
                return (electedCols, electedRows)
            }
            // Never announce SwiftTerm's unmeasured 80x25 default: a connect-
            // time claim with it reflowed the PTY to 80x25 and then, 400ms
            // later, to the real fit — two reflows per open, part of the size
            // flicker (probe 2026-10-01: "active_size 80x25" then "51x50").
            if let nat = view?.naturalFit() { return nat }
            return (t.cols, t.rows)
        }
        /// Whether we have a real measurement to claim with at connect.
        private func canClaimAtConnect() -> Bool { view?.naturalFit() != nil }

        /// Foreground wake: a socket that LOOKS live may be half-open.
        /// Ping it; the failure path feeds the normal reconnect machinery,
        /// and the blip-grace keeps a healthy pong invisible.
        func verifyAliveOnWake() {
            guard isLive, !sessionEnded else { return }
            wakeMark("liveness ping")
            client.verifyLiveness()
        }

        /// THE INVARIANT: while this phone is foreground, on screen, and not
        /// deliberately observing someone else's grid, the terminal it DRAWS
        /// must be the terminal that FITS its screen. Any violation is the
        /// "wrong size when I come back" bug.
        ///
        /// Four healers used to patch violations after the fact — the attach
        /// claim, the keyboard settle, the touch reclaim, the 5s polite retry
        /// — and every one of them missed the same edge: waking to a socket
        /// that SURVIVED the idle. Nothing re-checked anything, so a PTY the
        /// desk resized while the phone slept (the backgrounded phone adopts
        /// it silently — the deferred-adopt grace only applies while active)
        /// stayed wrong until the session was closed and reopened. Reopening
        /// "fixed" it for exactly one reason: a fresh attach claims the size
        /// DELIBERATELY, and the daemon lets an explicit human claim win
        /// outright (hop2 rooms.ts, `user: true`).
        ///
        /// So: waking with this terminal in your hand IS that same deliberate
        /// act. This is the one enforcement point; call it from every edge
        /// where the world may have moved under us.
        @discardableResult
        func maintainOwnFit(reason: String) -> Bool {
            // Only ever maintains a size we ALREADY own. It never contests a
            // peer's grid — a claim against another window comes from one
            // place now, and that place is a keystroke.
            guard isLive, !sessionEnded, !observeOnly, userIsLooking,
                  let v = view else { return false }
            if peerHoldsSize {
                // Not ours to maintain — but the keyboard/settle that got us
                // here may have changed what this screen would fit, and the
                // server's record of our declared fit must stay fresh (a
                // keystroke applies it sight-unseen). Declare, never contest.
                if let nat = v.naturalFit(), nat.cols > 1, nat.rows > 1 {
                    wakeMark("\(reason) declare \(nat.cols)x\(nat.rows) (peer holds)")
                    declareSize(nat.cols, nat.rows, reason: reason)
                }
                return false
            }
            // Re-fit to the CURRENT bounds before reading anything: after a
            // wake the cached fit can still describe the pre-lock layout
            // (keyboard up, different safe area), and claiming stale dims is
            // how a deliberate claim wins the election at the WRONG size.
            v.setNeedsLayout()
            v.layoutIfNeeded()
            let t = v.getTerminal()
            // naturalFit, NOT the raw fittedCols/Rows: the record can
            // describe a viewport that no longer exists, and the layout pass
            // above does not refresh it when the fit equals the size the
            // terminal already has. The settle check once "healed" a healthy
            // 62x47 grid down to a stale 28-row fit exactly this way —
            // that re-assert IS the half-screen bug.
            guard let nat = v.naturalFit(), nat.cols > 1, nat.rows > 1 else { return false }
            let cols = nat.cols, rows = nat.rows
            guard t.cols != cols || t.rows != rows else {
                wakeMark("\(reason) ok \(cols)x\(rows)")
                return false
            }
            let sinceLast = Date().timeIntervalSince(lastReclaimAt)
            guard sinceLast > 1 else {
                // Rate-limited — but never DROPPED: the keyboard's last frame
                // landed 80ms after a settle claim, this re-check was the
                // only thing that would have corrected it, and it vanished
                // silently; a 39-row grid sat in a 32-row view until the
                // next keystroke (diagnostic 2026-10-03). Re-run when allowed.
                wakeMark("\(reason) MISMATCH grid=\(t.cols)x\(t.rows) fit=\(cols)x\(rows) — rate-limited, retry")
                settleTask?.cancel()
                settleTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(Int((1.05 - sinceLast) * 1000)))
                    guard let self, !Task.isCancelled, self.claimed else { return }
                    self.maintainOwnFit(reason: "settle-retry")
                }
                return false
            }
            lastReclaimAt = Date()
            wakeMark("\(reason) MISMATCH grid=\(t.cols)x\(t.rows) fit=\(cols)x\(rows) — re-asserting")
            // POLITE. Maintaining our own grid must never outrank a human
            // typing somewhere else.
            client.sendResize(cols: cols, rows: rows)
            #if DEBUG
            if let marker = ProcessInfo.processInfo.environment["HOP_CLAIM_MARKER"] {
                try? "\(cols)x\(rows)\n".write(toFile: marker, atomically: true, encoding: .utf8)
            }
            #endif
            return true
        }

        /// Wake is not one moment: the keyboard, the safe areas and SwiftUI's
        /// own layout can still be landing when scenePhase flips. Enforce now
        /// for the common case, then once more after the dust settles — the
        /// mismatch gate makes the second call free when the first one worked.
        func runWakeCheck() {
            // Liveness ONLY. Waking used to re-claim the size, on the theory
            // that a screen in your hand is a deliberate act; Jian took that
            // back ("still only keystroke should"), and he is right that it
            // was a race: two clients each treating their own presence as
            // intent is exactly how a grid ends up matching neither.
            verifyAliveOnWake()
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
            connectStartedAt = Date()
            wakeEpochReset("foreground-reconnect")
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
            verifyThenConnect()
        }

        /// Give the keyboard back after a sheet took it.

        /// Text handed in from the app — an uploaded photo's path. Through
        /// deliver(), so it buffers while disconnected exactly like typing.
        @objc private func insertText(_ note: Notification) {
            guard let text = note.object as? String, !text.isEmpty else { return }
            deliver(text)
        }

        @objc private func dropKeyboard() {
            _ = view?.resignFirstResponder()
        }

        @objc private func refocusTerminal() {

            guard let v = view, v.window != nil, !v.isFirstResponder else { return }

            _ = v.becomeFirstResponder()

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
            case .shift:
                shiftArmed.toggle()
                view?.setShiftArmed(shiftArmed)
            case .cmd:
                cmdArmed.toggle()
                view?.setCmdArmed(cmdArmed)
            case .dismiss:
                _ = view?.resignFirstResponder()
            case .board:
                view?.toggleHopBoard()
            case .shiftEnter:
                view.map { deliver($0.shiftEnterSequence()) }
            case .paste:
                // Through SwiftTerm, not straight down the socket: when the
                // app has bracketed paste on, it wraps the text in
                // ESC[200~ / ESC[201~ so a multi-line paste arrives as ONE
                // paste. Sending it raw meant every newline executed a line —
                // and pasting is exactly what you do on a phone instead of
                // typing. Its send path still lands in deliver(), so buffering
                // while disconnected keeps working.
                view?.paste(nil)
            case .up, .down, .left, .right, .shiftUp, .shiftDown, .shiftLeft, .shiftRight:
                // xterm modified arrows: CSI 1;<1+shift+2·alt+4·ctrl> X. The
                // armed modifiers used to be ignored here (a plain arrow went
                // out under an armed ctrl), so ctrl+→ word jumps never worked
                // either. One-shot, like the typed-text path.
                let seq = arrowSequence(key, shift: shiftArmed, alt: altArmed,
                                        ctrl: ctrlArmed, cmd: cmdArmed)
                clearArmedModifiers()
                if let seq { deliver(seq) }
            default:
                if let seq = key.sequence { deliver(seq) }
            }
            // Only the press buzzes. A held key repeats ~18x a second, and
            // haptics on every tick is a drill, not feedback.
            if !isRepeat { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        }

        // ── TerminalViewDelegate ──
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            guard let text = String(bytes: data, encoding: .utf8) else { return }
            // The EMULATOR answering an app's query (cursor position, device
            // attributes, focus, colours) is not the user typing. It used to
            // run the keystroke path — reclaim the size (user:true) and mark
            // typing — so every Codex redraw-and-query made the phone grab
            // the size, the desk's own answer grabbed it back, and the PTY
            // flipped 56x32 <-> 114x33 every 20–40ms (diagnostic 2026-10-05).
            if Self.isTerminalReply(text) {
                // While another device holds the size, ITS emulator answers
                // the app; a second answer from us only feeds the loop.
                if peerHoldsSize { return }
                client.sendInput(text)
                return
            }
            typedText(text)
        }

        /// A payload made ONLY of terminal-generated reports (mirrors hop2
        /// rooms.ts PURE_MOUSE_REPORT, minus mouse — taps send those on purpose).
        static let replyPattern = try! NSRegularExpression(pattern:
            "^(?:\\x1b\\[\\d+;\\d+R|\\x1b\\[[?>=][\\d;]*c|\\x1b\\[[IO]|\\x1b\\[\\??[\\d;]+\\$y"
            + "|\\x1b\\[\\?\\d+u|\\x1b\\[\\d+n|\\x1b\\[\\d+(?:;\\d+)*t"
            + "|\\x1b\\][^\\x07\\x1b]*(?:\\x07|\\x1b\\\\)|\\x1bP[^\\x1b]*\\x1b\\\\)+$")
        static func isTerminalReply(_ text: String) -> Bool {
            let r = NSRange(text.startIndex..., in: text)
            return replyPattern.firstMatch(in: text, range: r) != nil
        }

        /// The one path every typed character takes, from either keyboard:
        /// armed modifiers apply, then deliver (which buffers, reclaims the
        /// size, and marks typing).
        /// Every armed modifier lets go after one key, exactly like a Mac's
        /// sticky keys and like the arrows above.
        private func clearArmedModifiers() {
            if ctrlArmed { ctrlArmed = false; view?.setCtrlArmed(false) }
            if altArmed { altArmed = false; view?.setAltArmed(false) }
            if shiftArmed { shiftArmed = false; view?.setShiftArmed(false); view?.clearBoardShift() }
            if cmdArmed { cmdArmed = false; view?.setCmdArmed(false) }
        }

        /// ⌘C on a Mac terminal copies what's SELECTED, or the screen when
        /// nothing is — never the shell's ^C.
        private func copySelectionOrScreen() {
            if let sel = view?.getSelection(), !sel.isEmpty {
                UIPasteboard.general.string = sel
                onToast("Copied")
            } else {
                copyScreen()
            }
        }

        func typedText(_ raw: String) {
            // ⇧ + return: the Mac's newline-without-submit (the ⇧⏎ key is the
            // same thing in one tap).
            if shiftArmed, raw == "\r" || raw == "\n" {
                clearArmedModifiers()
                view.map { deliver($0.shiftEnterSequence()) }
                return
            }
            guard raw.count == 1, let ch = raw.first,
                  ctrlArmed || altArmed || cmdArmed else { deliver(raw); return }
            // ⌘C / ⌘V never touch the wire, so they work in EVERY app — which
            // is what they do on a Mac.
            if cmdArmed, !ctrlArmed, !altArmed, let low = ch.lowercased().first {
                if low == "c" { clearArmedModifiers(); copySelectionOrScreen(); return }
                if low == "v" { clearArmedModifiers(); view?.paste(nil); return }
            }
            let enhanced = view?.enhancedKeys ?? false
            let seq = modifiedKey(ch, shift: shiftArmed, alt: altArmed, ctrl: ctrlArmed,
                                  cmd: cmdArmed, enhanced: enhanced)
            clearArmedModifiers()
            guard let seq else {
                // Only CSI-u carries ⌘, and this app never asked for it.
                onToast("⌘\(ch.uppercased()) needs an app that reads it — claude and codex do")
                return
            }
            deliver(seq)
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
        /// True from the second connect on: the wake path. A fresh open
        /// waits 400ms for the keyboard's layout; a reconnect's view is
        /// already laid out, and every ms of that delay was a ms the
        /// foreign grid stayed on screen.
        private var everConnected = false
        /// Set at every connect entry; the adopt-defer window is measured
        /// from here.
        private var connectStartedAt = Date.distantPast
        private func adoptForeign(cols: Int, rows: Int) {
            guard let tv = view else { return }
            wakeMark("adopt \(cols)x\(rows)")
            Logger(subsystem: "io.zhoulab.hop.spike", category: "layout")
                .info("room elected \(cols)x\(rows), we draw \(tv.drawnCols)x\(tv.drawnRows) — adopting; drags pan")
            peerHoldsSize = true
            // RESIZE FIRST, then tell SwiftUI. The other order re-rendered the
            // representable while the terminal still held the OLD grid, so the
            // auto-scale computed a font for a width that was no longer there
            // and left the peer's wide grid drawn at full size and CROPPED —
            // probe-caught: a 100x24 grid filling the top-left quarter of the
            // screen with the "take mine" chip already up.
            tv.pinnedGrid = (cols, rows)
            tv.getTerminal().resize(cols: cols, rows: rows)
            onSizeState("\(cols)×\(rows)")
            startReclaimRetry()
            // Repaint EVERY cell after a reflow. SwiftTerm redraws the rows it
            // knows changed, and a resize invalidates that bookkeeping — which
            // is how a grid change leaves "the last few lines messed up"
            // (Jian). updateFullScreen marks the whole buffer dirty; the
            // display pass then has nothing stale to preserve.
            tv.getTerminal().updateFullScreen()
            tv.setNeedsDisplay(tv.bounds)
            tv.applyLetterbox()
            tv.scheduleSettleRedraw("adopt-foreign")
            onGridChange()
        }
        /// Hand THIS session's state to the host, from inside the session.
        ///
        /// The Account sheet's version was useless for the bug it was built
        /// for: reaching it means leaving the terminal, and leaving rebuilds
        /// the view — which HEALS a render fault, so the trace that arrives
        /// describes a screen that has already recovered (Jian: "the very act
        /// of returning to the main menu may have erased the problem"). This
        /// one captures the numbers before anything has a chance to settle,
        /// and says WHICH session, so a fault in one of twenty-three is not
        /// an anonymous log.
        func sendSessionDiagnostics() {
            guard let tv = view else { return }
            let t = tv.getTerminal()
            let nat = tv.naturalFit()
            let text = """
            session: \(room)
            grid: \(t.cols)x\(t.rows)   drawn: \(tv.drawnCols)x\(tv.drawnRows)   cap: \(tv.capCols)x\(tv.capRows)
            pinned: \(tv.pinnedGrid.map { "\($0.cols)x\($0.rows)" } ?? "nil")   \
            natural: \(nat.map { "\($0.cols)x\($0.rows)" } ?? "nil")
            elected: \(electedCols)x\(electedRows)   peerHoldsSize: \(peerHoldsSize)
            bounds: \(Int(tv.bounds.width))x\(Int(tv.bounds.height))   \
            content: \(Int(tv.contentSize.height))   offset: \(Int(tv.contentOffset.y))
            font: \(String(format: "%.1f", tv.font.pointSize)) (natural \(Int(tv.naturalFontPt)))
            altScreen: \(tv.remoteAltScreen)   chromeOverlap: \(Int(tv.chromeOverlap))

            keyboard/fit trace (newest last):
            \(KBLog.dump())
            """
            let label = room.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "",
                                                  options: .regularExpression)
            guard let url = URL(string: httpBase)?.appendingPathComponent("api/diagnostics")
            else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.timeoutInterval = 15
            if let tok = token_, !tok.isEmpty {
                req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["label": label, "text": text])
            let sess = urlSession
            Task { @MainActor [weak self] in
                let ok = (try? await sess.data(for: req))
                    .map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
                self?.onToast(ok ? "Diagnostics sent to hop" : "Could not send diagnostics")
            }
        }

        /// The wake instrument (PLAN 17), now RELEASE-visible: every
        /// size-relevant event lands in the KBLog ring (Copy diagnostics),
        /// so "wrong size when idle and back" on the real phone is one
        /// paste away from a named culprit. The env-gated file marker stays
        /// for probes.
        private var wakeEpoch = Date()
        func wakeMark(_ line: String) {
            let ms = Int(Date().timeIntervalSince(wakeEpoch) * 1000)
            KBLog.record("wake t+\(ms)ms \(line)")
            #if DEBUG
            guard let path = ProcessInfo.processInfo.environment["HOP_WAKE_MARKER"] else { return }
            let entry = "t+\(ms)ms \(line)\n"
            if let h = FileHandle(forWritingAtPath: path) {
                h.seekToEndOfFile(); h.write(Data(entry.utf8)); try? h.close()
            } else {
                try? entry.write(toFile: path, atomically: true, encoding: .utf8)
            }
            #endif
        }
        func wakeEpochReset(_ reason: String) {
            wakeEpoch = Date()
            wakeMark("== \(reason)")
        }

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

        /// Keyboard switches (system ↔ emoji ↔ third-party) fire a burst of
        /// frame changes, and the LAST one sometimes leaves the grid sized
        /// for a keyboard that's gone — Jian, on device: "sometimes the
        /// terminal size becomes too small compared to the space left".
        /// After the burst settles, verify the grid against what the view
        /// currently fits, and re-assert when they disagree. A no-op when
        /// everything is consistent.
        private var settleTask: Task<Void, Never>?

        /// While a keyboard transition is in flight, fits are RECORDED but not
        /// sent. Angler's trace named why: the system reports two keyboard
        /// heights 17pt apart (h=354 and h=371 — with and without the
        /// assistant strip), each flip re-fit 40↔38 rows and re-claimed, and
        /// whichever half of the pair was stale left the session ending a
        /// strip above the keys. One PTY means every client reflowed per
        /// flip, twice per keyboard toggle. The settle check 700ms after the
        /// LAST frame event sends the one claim that describes where the
        /// keyboard actually came to rest.
        private var kbChurnAt = Date.distantPast
        var inKeyboardChurn: Bool { Date().timeIntervalSince(kbChurnAt) < 0.7 }
        /// Stamped DIRECTLY from the keyboard notification, not through the
        /// SwiftUI controlAction round trip: that detour costs a couple of
        /// frames, and the trace shows a fit arriving 2ms after the keyboard
        /// frame — inside the churn, outside the late-opened window. It was
        /// the one fit that mattered.
        @objc func noteKeyboardChurn() { kbChurnAt = Date() }

        func scheduleKeyboardSettleCheck() {
            kbChurnAt = Date()
            // The repaint half is unconditional: a keyboard move shifts the
            // view under any in-flight draw whether or not we own the grid,
            // and a quiet session leaves whatever that draw painted.
            view?.scheduleSettleRedraw("keyboard")
            settleTask?.cancel()
            settleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                guard let self, !Task.isCancelled, self.claimed else { return }
                // Same invariant, same enforcement — this used to send a
                // POLITE resize that a typing peer could refuse, and it
                // skipped the peer-held case entirely, which is precisely
                // the case a keyboard switch lands you in.
                self.maintainOwnFit(reason: "settle")
            }
        }

        private func startReclaimRetry() {
            reclaimTimer?.invalidate()
            // Deliberately EMPTY since 2026-07-31. This used to re-assert the
            // attach intent every 5s while a peer held the grid — a claim with
            // no keystroke behind it, which is precisely the design Jian asked
            // to eliminate ("we do not trigger in the background if no user
            // interaction observed"). The chip and the next keystroke are the
            // two honest ways back.
        }

        private func stopReclaimRetry() {
            reclaimTimer?.invalidate()
            reclaimTimer = nil
        }

        private func claimSizeOnAttach() {
            // Fresh open: the keyboard's layout is still landing — wait a
            // beat and claim once at the size we'll keep. Reconnect/wake:
            // the layout already exists, so the claim goes out NOW; the
            // 400ms was a third of the wake-flash (Jian: "why does idle
            // change the size?").
            // The 400ms guarded a first connect whose layout didn't exist yet;
            // when the natural fit is already valid there is nothing to wait
            // for, and every ms is a wrong-size frame on a server without the
            // connect-time claim.
            let fitReady = (view?.naturalFit()?.cols ?? 0) > 1
            let delayMs = (everConnected || fitReady) ? 0 : 400
            everConnected = true
            Task { @MainActor [weak self] in
                if delayMs > 0 { try? await Task.sleep(for: .milliseconds(delayMs)) }
                self?.sendAttachClaim()
            }
        }

        private func sendAttachClaim() {
            guard !claimed, !observeOnly else { return }
            claimed = true
            // Claim what IS, not what was: after a wake the cached fit can
            // describe the PRE-LOCK layout (keyboard rows included), and a
            // deliberate claim with stale dims WINS the election with the
            // wrong size — "often wrong when idle and back" (Jian, on 260).
            // A synchronous layout pass makes SwiftTerm re-fit the CURRENT
            // bounds and fire sizeChanged before we read.
            if let v = view {
                v.setNeedsLayout()
                v.layoutIfNeeded()
            }
            let t = view?.getTerminal()
            // The NATURAL fit at the user's font. While a peer's grid is
            // adopted, fittedCols/Rows describe the auto-scaled font — they
            // match the foreign grid by construction, and claiming them
            // would re-propose the peer's own size as ours.
            let nat = view?.naturalFit()
            let cols = (nat?.cols ?? 0) > 1 ? nat!.cols : (fittedCols > 0 ? fittedCols : (t?.cols ?? 0))
            let rows = (nat?.rows ?? 0) > 1 ? nat!.rows : (fittedRows > 0 ? fittedRows : (t?.rows ?? 0))
            guard cols > 0, rows > 0 else { return }
            // A pocket reconnect claims NOTHING. This used to send the claim
            // regardless and merely drop the deliberate flag — so a socket
            // that re-established itself while the phone was face-down still
            // reshaped a PTY someone was typing in, whenever nobody had typed
            // inside the idle window. Skipping is safe now that the wake
            // check exists: returning to the app re-establishes the size
            // invariant immediately, which is exactly when it should happen.
            guard userIsLooking else {
                wakeMark("claim \(cols)x\(rows) SKIPPED (inactive) — wake will claim")
                return
            }
            // POLITE attach. Opening a session is not a bid to take the grid
            // away from whoever is typing in it: the daemon grants this when
            // nobody has typed recently and refuses otherwise, and a refusal
            // just means we render their grid scaled until you type.
            wakeMark("claim \(cols)x\(rows) polite")
            view?.walkMark("attach-claim \(cols)x\(rows)")
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
            KBLog.record("fit \(newCols)x\(newRows) bounds=\(Int(source.bounds.width))x\(Int(source.bounds.height)) font=\(String(format: "%.1f", source.font.pointSize)) cell=\(String(format: "%.2f", source.bounds.width / CGFloat(max(newCols, 1))))")
            fittedCols = newCols
            fittedRows = newRows
            view?.drawnRows = newRows
            view?.drawnCols = newCols
            // The bounds AND FONT this measurement DESCRIBES. SwiftTerm
            // reports a fit only when it changes the terminal size, so these
            // numbers can outlive both the viewport AND the font size they
            // were measured in (see scaledFit). Recording only the bounds was
            // not enough: a transient font (auto-scale reacting to a default
            // 80x25 mid-keyboard-animation) measured 64x19 at the FULL
            // bounds, so naturalFit saw measuredAt==bounds and trusted 19
            // rows as exact — locking in half the screen even after the font
            // corrected back to natural, because no new sizeChanged fired.
            view?.drawnBounds = source.bounds.size
            view?.drawnFontPt = source.font.pointSize
            // Loud when a measurement was taken at a font far from natural —
            // the upstream cause of a font-mismatched half-height. Its
            // presence in a future trace confirms this heal is engaging.
            if let tv = view, tv.naturalFontPt > 0.1,
               abs(source.font.pointSize - tv.naturalFontPt) > 3 {
                KBLog.record("fit \(newCols)x\(newRows) measured at OFF-natural font "
                    + "\(String(format: "%.1f", source.font.pointSize)) (natural \(Int(tv.naturalFontPt))) — will rescale")
            }
            view?.applyLetterbox()
            // Observer mode's convergence: a font change refits the terminal
            // locally, and if fewer columns fit than the room elected, the
            // adopted grid has been silently defeated. Nudge the font smaller
            // (bounded) until SwiftTerm itself reports enough columns, then
            // snap the grid back to the exact elected size.
            if observeOnly || autoScaling, electedCols > 1 {
                if newCols < electedCols, fitNudges < 8 {
                    fitNudges += 1
                    DispatchQueue.main.async { self.onGridChange() }
                } else if newCols != electedCols {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.observeOnly,
                              let t = self.view?.getTerminal(),
                              t.cols != self.electedCols else { return }
                        self.view?.walkMark("local resize → \(self.electedCols)x\(self.electedRows)")
                        t.resize(cols: self.electedCols, rows: self.electedRows)
                    }
                }
            }
            // Before the claim, record only. Sending now would reshape the PTY
            // at a height the keyboard is about to take away. Observer mode
            // suppresses everything: that geometry is borrowed on purpose.
            guard claimed, !observeOnly else { return }
            // And never while nobody is looking (Jian: "the app keeps
            // resizing the terminal even when it is inactive"). iOS re-lays
            // this view out for reasons that have nothing to do with the
            // user — the app-switcher snapshot on the way to the background
            // is the loud one — and every such refit used to reshape a PTY
            // someone else was working in. The fit is still RECORDED; the
            // wake check re-establishes it the moment he is back.
            guard userIsLooking else {
                wakeMark("fit \(newCols)x\(newRows) recorded, not sent (inactive)")
                return
            }
            Logger(subsystem: "io.zhoulab.hop.spike", category: "layout")
                .info("fit \(newCols)x\(newRows) in \(Int(source.bounds.height))pt view, accessory \(Int(source.inputAccessoryView?.bounds.height ?? 0))pt")
            // Mid-transition fits stay local: the settle check claims the
            // final one. Sending each intermediate is how the 38↔40 flap
            // reflowed the PTY twice per keyboard toggle (see kbChurnAt).
            guard !inKeyboardChurn else {
                wakeMark("fit \(newCols)x\(newRows) deferred (kb churn)")
                return
            }
            reassertOwnFit(cols: newCols, rows: newRows)
        }

        // THE PAN-STUCK BUG (Jian, on device: "sometimes pannable but not
        // scrollable, typing does not fix it, back and reenter does"):
        // pinnedGrid can end up larger than what the view can actually draw
        // — an active_size confirmed as OURS pins to that confirmed size
        // without re-validating it against current bounds, and if
        // bounds/font were transiently stale at claim time (mid-rotation,
        // mid-keyboard-animation), the confirmed size silently doesn't fit.
        // peerSizedGrid then reads true (pan engages) while peerHoldsSize
        // reads false (no chip) — the exact reported symptom.
        //
        // Shared by two callers: sizeChanged (a REAL layout pass — cols/rows
        // are what SwiftTerm's own bounds-based fit just measured) and
        // handleScrollPan's pan-begin (a SYNTHETIC check — cols/rows are
        // naturalFit()'s measurement, used because a device log showed
        // sizeChanged can simply not fire again for a long stretch after a
        // wake, leaving a pan stuck with nothing to notice the mismatch).
        // Deliberately does NOT touch drawnCols/drawnRows/fittedCols/Rows —
        // those describe what a REAL layout pass measured, and the pan-begin
        // caller's guess must never be mistaken for one, or a legitimate
        // peer-held oversized grid's letterbox/pan math would compute off a
        // value nobody's layout pass actually reported.
        fileprivate func reassertOwnFit(cols: Int, rows: Int) {
            guard claimed, !observeOnly, userIsLooking else { return }
            if peerHoldsSize {
                // Declare, don't contest: keep the server's record of OUR
                // natural fit fresh while a peer owns the grid (rotation,
                // keyboard changes), so the next keystroke's ownership
                // transfer lands at the right size. A non-owner's resize
                // never moves the PTY — the server just answers with the
                // grid we are already drawing. Deliberately IGNORES the
                // cols/rows this was called with and re-measures naturalFit()
                // itself: a caller's cols/rows can be the auto-scaled fit
                // (sizeChanged's newCols/newRows, while a peer's grid has us
                // scaled down) — declaring THAT would propose the peer's own
                // size back as ours, which confirms as OURS by construction.
                if let nat = view?.naturalFit(), nat.cols > 1, nat.rows > 1 {
                    declareSize(nat.cols, nat.rows, reason: "peer holds")
                }
                return
            }
            if let pin = view?.pinnedGrid, pin != (cols, rows) {
                wakeMark("fit MISMATCH pinned=\(pin.cols)x\(pin.rows) natural=\(cols)x\(rows) — re-pinning")
                view?.pinnedGrid = (cols, rows)
                // Apply LOCALLY too, now — the old re-pin waited for the
                // server's active_size round trip (or the next layout pass)
                // to actually resize the terminal, so the stuck pan stayed
                // stuck for the gesture that triggered the heal, and forever
                // if the socket was down.
                if let t = view?.getTerminal(), t.cols != cols || t.rows != rows {
                    self.view?.walkMark("local resize → \(cols)x\(rows)")
                    t.resize(cols: cols, rows: rows)
                    t.updateFullScreen()
                    view.map { $0.setNeedsDisplay($0.bounds) }
                    view?.applyLetterbox()
                    onGridChange()
                }
            }
            declareSize(cols, rows, reason: "fit")
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
            if hv?.selectionActive == true { hv?.selectMark("scrolled while selected pos=\(position) yDisp=\(t.buffer.yDisp)") }
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
                hv.selectMark("anchor ← \(hv.historyAnchor.map(String.init) ?? "nil") pos=\(position) yDisp=\(t.buffer.yDisp) hasHistory=\(hasHistory)")
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
            onBell()
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}

// ── Accessory key bar ──
enum AccessoryKey: Equatable {
    case esc, tab, shiftTab, ctrl, alt, ctrlC, up, down, left, right
    case shiftUp, shiftDown, shiftLeft, shiftRight
    case shift, cmd
    case pipe, slash, dash, tilde, pageUp, pageDown, paste, dismiss, backspace, shiftEnter
    /// Toggles the hop keyboard (HopBoardView as inputView) — a view
    /// concern, handled by HopTermView itself, so sequence is nil.
    case board
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
        case .shiftUp: return "\u{1b}[1;2A"
        case .shiftDown: return "\u{1b}[1;2B"
        case .shiftLeft: return "\u{1b}[1;2D"
        case .shiftRight: return "\u{1b}[1;2C"
        case .board: return nil
        // Not static: CSI 13;2u for an app that understands it, plain enter
        // for a shell that would print it as junk. The tap handler asks the
        // view, which tracks the protocol from output.
        case .shiftEnter: return nil
        // paste is not a static sequence: it goes through the view so the
        // app's bracketed-paste mode is honoured. See the handler.
        case .paste, .ctrl, .alt, .shift, .cmd, .dismiss: return nil
        }
    }

    var spokenName: String {
        switch self {
        case .shiftTab: return "shift tab"
        case .cmd: return "command"
        case .shiftUp: return "shift up"
        case .shiftDown: return "shift down"
        case .shiftLeft: return "shift left"
        case .shiftRight: return "shift right"
        case .ctrlCombo(let ch): return "control \(ch)"
        case .backspace: return "backspace"
        case .shiftEnter: return "shift return"
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
    /// Text typed on the hop keyboard: routed through the SAME ctrl/alt
    /// arming as system-keyboard text, so ctrl+c works from either board.
    func typedText(_ text: String)
    /// Scrolling, which is NOT typing — see the implementation for why that
    /// distinction has to exist at all.
    func scrollInput(_ text: String)
    /// The hop keyboard's ⇧: one-shot, applies to the next accessory arrow.
    func setShiftArmed(_ on: Bool)
}
extension AccessoryKeyHandler {
    func accessoryKey(_ key: AccessoryKey) { accessoryKey(key, isRepeat: false) }
    func setShiftArmed(_ on: Bool) {}
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
    private weak var chromeTapTwoFinger: UITapGestureRecognizer?
    private weak var clickTap: UITapGestureRecognizer?
    /// Big enough for a thumb, small enough not to steal taps meant for the
    /// first line of output. The grid extends under the status bar now, so
    /// the strip must too — a fixed 46 left the tappable band almost
    /// entirely inside the status area (probe-caught: the summon tap fell
    /// through to the keyboard).
    static var chromeStrip: CGFloat { windowTopInset() + 46 }
    /// How tall the chrome overlay actually is RIGHT NOW — the bar alone, or
    /// bar + expanded Views strip. Set by the host. Everything that asks "is
    /// this touch on the chrome" must use this, not the bar-only constant:
    /// with the strip open, a tap on the back button was ALSO counted as a
    /// body tap by the terminal underneath, which collapsed the strip on the
    /// same touch and re-laid the overlay out from under the button (Jian:
    /// "the back button is disabled when the view list is expanded").
    var chromeHeightNow: CGFloat = 0
    var chromeReach: CGFloat { max(Self.chromeStrip, chromeHeightNow) }

    /// A link was tapped directly on the grid.
    var onOpenLink: ((String) -> Void)?

    /// The URL under a tap, or nil. Rows are padded to the grid width and
    /// joined without separators, so wrapped URLs connect and the offset
    /// math is exact — see linkHit. Built per tap; the grid is small.
    /// Point → grid cell, in the geometry the view is ACTUALLY drawing: the
    /// fit SwiftTerm reports at the current (possibly scaled) font, not the
    /// natural-font cap. A peer-sized session is auto-scaled so a desktop's
    /// 62 columns fit this width; mapping taps through the 51-column natural
    /// cap put every tap ~20% off — rows away from the URL under the finger
    /// (Jian, on Codex sessions the desktop hub drives: "cannot click urls").
    /// The cap is the PAN verdict's business; pixels belong to the drawn fit.
    /// In pan mode the content is the whole grid in content coordinates, so
    /// the viewport offset is the pan, not a scroll into history.
    func cellAt(_ locInView: CGPoint) -> (row: Int, col: Int, cellW: CGFloat, cellH: CGFloat)? {
        let t = getTerminal()
        let drawnFit = scaledFit(bounds: bounds.size, measuredAt: drawnBounds,
                                 drawnCols: drawnCols, drawnRows: drawnRows, fontRatio: 1)
        let cols = max(1, drawnFit?.cols ?? (drawnCols > 0 ? drawnCols : t.cols))
        let rows = max(1, drawnFit?.rows ?? (drawnRows > 0 ? drawnRows : t.rows))
        let cellW = bounds.width / CGFloat(cols)
        let cellH = bounds.height / CGFloat(rows)
        let liveTop = CGFloat(t.buffer.yDisp) * cellH
        let x = peerSizedGrid ? locInView.x : locInView.x - bounds.origin.x
        let y = peerSizedGrid ? locInView.y - liveTop : locInView.y - bounds.origin.y
        let row = Int(y / max(1, cellH)), col = Int(x / max(1, cellW))
        guard row >= 0, row < t.rows, col >= 0, col < t.cols else { return nil }
        return (row, col, cellW, cellH)
    }

    /// The longest URL anywhere in the buffer (scrollback included, both
    /// screens) that starts with `prefix` and is longer than it.
    private func fullURL(withPrefix prefix: String) -> String? {
        guard prefix.count >= 12 else { return nil }
        let t = getTerminal()
        var best: String?
        let lines = t.getBufferAsData(kind: .normal) + Data([10]) + t.getBufferAsData(kind: .alt)
        let text = String(decoding: lines, as: UTF8.self)
        var search = text.startIndex
        while let r = text.range(of: prefix, range: search..<text.endIndex) {
            var end = r.upperBound
            while end < text.endIndex, isUrlChar(text[end]) { end = text.index(after: end) }
            let cand = String(text[r.lowerBound..<end])
            if cand.count > prefix.count, cand.count > (best?.count ?? 0) { best = cand }
            search = r.upperBound
        }
        return best
    }

    func linkUnderTap(_ locInView: CGPoint) -> String? {
        guard let cell = cellAt(locInView) else { return nil }
        return linkAt(row: cell.row, col: cell.col)
    }

    #if DEBUG
    /// HOP_LINK_SCAN=<file>: what a tap on each cell would open, one line per
    /// distinct link — the real lookup, without having to aim a finger.
    func debugScanLinks(to path: String) {
        let t = getTerminal()
        var seen: [String] = []
        for r in 0..<t.rows {
            for c in stride(from: 0, to: t.cols, by: 2) {
                if let l = linkAt(row: r, col: c, log: false), !seen.contains(l) { seen.append(l) }
            }
        }
        try? (seen.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }
    #endif

    func linkAt(row: Int, col: Int, log: Bool = true) -> String? {
        let t = getTerminal()
        // Rows padded to the grid width; linkHit(rows:) joins wrapped ones
        // (an app's indented continuation included) and maps the tap exactly.
        var rows: [String] = []
        rows.reserveCapacity(t.rows)
        for r in 0..<t.rows {
            var line = t.getLine(row: r)?.translateToString(trimRight: true) ?? ""
            if line.count > t.cols { line = String(line.prefix(t.cols)) }
            rows.append(line.padding(toLength: t.cols, withPad: " ", startingAt: 0))
        }
        // Explicit hyperlinks first (OSC 8): Codex SHORTENS long URLs on
        // screen ("https://hop.zhoulab.io/view/Accessibility-for…") and the
        // visible text is all the scan below can see — so a tap opened a
        // truncated, dead address (Jian: "tap link to open in codex still
        // broken"). The escape carries the full URL; SwiftTerm keeps it.
        let explicit = t.link(at: .screen(Position(col: col, row: row)), mode: .explicitOnly)
        var hit = explicit ?? linkHit(rows: rows, row: row, col: col)
        // No embedded link, but the visible one is truncated: the full URL
        // is usually printed in full somewhere else (scrollback, an earlier
        // line). Take the longest URL there that starts with the visible
        // prefix; otherwise drop the "…" rather than open garbage.
        // The scan stops AT the ellipsis (not a URL character), so the hit
        // itself looks whole; the screen text right after it says otherwise.
        let screenText = rows.joined()
        if explicit == nil, let h = hit,
           h.hasSuffix("…") || h.hasSuffix("...") || screenText.contains(h + "…") || screenText.contains(h + "...") {
            let stem = h
                .replacingOccurrences(of: "…", with: "")
                .replacingOccurrences(of: "...", with: "")
            hit = fullURL(withPrefix: stem) ?? stem
            if log { KBLog.record("tap link truncated on screen: \(String(h.suffix(24))) → \(hit == stem ? "no full form found" : "recovered")") }
        }
        guard log else { return hit }
        KBLog.record("tap explicit=\(explicit != nil)")
        KBLog.record("tap r\(row) c\(col) drawn=\(drawnCols)x\(drawnRows) cap=\(capCols)x\(capRows) "
            + "grid=\(t.cols)x\(t.rows) pan=\(peerSizedGrid) cursor=r\(t.buffer.y)c\(t.buffer.x) "
            + "mouse=\(remoteTakesMouse) alt=\(remoteAltScreen) anchor=\(historyAnchor.map(String.init) ?? "nil") "
            + "link=\(hit.map { String($0.prefix(30)) } ?? "nil")")
        return hit
    }

    @objc private func handleChromeTap(_ g: UITapGestureRecognizer) {
        // Content can live UNDER the summon strip — a short session's whole
        // output does (Jian: "the session is too short, it appears too close
        // to the top that I cannot click on the link"). A tap that lands ON
        // a link opens it; the strip's chrome duty only applies to taps on
        // nothing.
        if let link = linkUnderTap(g.location(in: self)), let open = onOpenLink {
            open(link)
            return
        }
        onChromeTap?()
    }

    /// Records the geometry behind "the session moved up and took half the
    /// screen": whether this view still starts where the screen does. Cheap,
    /// and it turns the next occurrence into a measurement instead of a
    /// theory. Only logs when the top is actually off screen.
    private func logIfShiftedOffScreen() {
        guard let window else { return }
        let inWindow = convert(bounds, to: window)
        guard inWindow.minY < -1 else { return }
        KBLog.record("terminal shifted: topInWindow=\(Int(inWindow.minY)) "
            + "h=\(Int(inWindow.height)) window=\(Int(window.bounds.height)) "
            + "visible=\(Int(inWindow.intersection(window.bounds).height))")
    }

    /// Is this tap in the band that summons the chrome?
    ///
    /// Measured against the top of what is ON SCREEN, not the top of this
    /// view. When something shifts the terminal upward — keyboard avoidance
    /// is the usual cause — the view's own top leaves the screen and takes
    /// the strip with it, so tapping the topmost visible row did nothing and
    /// the session had no reachable way back (Jian: "no way to trigger the
    /// back menu"). The view-relative test is kept as the fast path; the
    /// window test only ever ADDS reachable area.
    private func inChromeStrip(_ g: UIGestureRecognizer) -> Bool {
        logIfShiftedOffScreen()
        if g.location(in: self).y - bounds.origin.y < chromeReach { return true }
        guard let window else { return false }
        let onScreen = convert(bounds, to: window).intersection(window.bounds)
        guard !onScreen.isNull else { return false }
        return g.location(in: window).y - onScreen.minY < chromeReach
    }

    /// Diagnostics only: which tap recognizers fire, and when, relative to a hold.
    @objc private func tapObserved(_ g: UITapGestureRecognizer) {
        selectMark("tap fired ours=\(g === clickTap || g === chromeTap || g === chromeTapTwoFinger) taps=\(g.numberOfTapsRequired) touches=\(g.numberOfTouchesRequired) sel=\(selectionActive)")
    }

    @objc private func handleClickTap(_ g: UITapGestureRecognizer) {
        // A tap that lands ON a URL means "open it" in any mode — claude's
        // own output is full of PR links, and sending a synthetic mouse
        // click at a URL instead of opening it helps nobody.
        if let link = linkUnderTap(g.location(in: self)), let open = onOpenLink {
            open(link)
            return
        }
        // Same drawn-geometry mapping as the link test above; SGR mouse
        // cells are 1-based.
        guard let cell = cellAt(g.location(in: self)) else {
            let t = getTerminal()
            walkMark("tap OFF-GRID y=\(Int(g.location(in: self).y)) grid=\(t.cols)x\(t.rows) "
                + "drawn=\(drawnCols)x\(drawnRows) pan=\(peerSizedGrid)")
            return
        }
        let row = cell.row + 1, col = cell.col + 1
        let cellW = cell.cellW, cellH = cell.cellH
        if remoteTakesMouse {
            onUserIntent?()
            keyHandler?.scrollInput(clickSequence(col: col, row: row))
        } else if let walk = arrowWalk(toRow: cell.row, col: cell.col) {
            // No mouse reporting (Codex): walk the cursor there with arrows.
            walkMark("walk to r\(cell.row) c\(cell.col) from r\(getTerminal().buffer.y) c\(getTerminal().buffer.x): \(walk.count / 3) arrows")
            // The tap IS the intent to be at the live edge; a held anchor
            // would drag the view back the moment the app redraws.
            if historyAnchor != nil {
                userScrollInFlight = true
                historyAnchor = nil
            }
            onUserIntent?()
            keyHandler?.scrollInput(walk)
        } else {
            return   // nowhere safe to walk — no haptic, no ghost
        }
        // Instant local confirmation. The cursor is CLAUDE's, so it only moves
        // after a network round-trip — with no local feedback the tap felt
        // like it missed, so you tapped again and the second click overshot
        // (Jian: "sometimes it works, sometimes it doesn't … I have to tap
        // several times"). A haptic + a caret ghost at the tapped cell say
        // "landed here" before the real cursor catches up.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        flashTapCaret(col: col, row: row, cellW: cellW, cellH: cellH)
    }

    /// Tap-to-position for apps WITHOUT mouse reporting — codex and claude
    /// (both INLINE TUIs, not alt-screen), and shells. Walk the cursor to the
    /// tapped cell with arrow keys, the way the two-finger trackpad does: in
    /// a composer the terminal cursor IS the caret.
    ///
    /// This used to demand `remoteAltScreen` for any vertical move, which
    /// silently reduced it to same-line nudges in exactly the apps it was
    /// built for — codex renders inline, so tapping an earlier line of a
    /// multiline prompt did nothing at all (Jian: "only works for the last
    /// line but not prev lines with multiline input"). The bound in
    /// `cursorWalk` is the real safety rail, not the screen mode.
    ///
    /// Only at the live edge: in scrollback the tapped row isn't the row the
    /// app's cursor is counting from.
    private func arrowWalk(toRow row: Int, col: Int) -> String? {
        // A held history anchor USED to refuse the walk outright. Tapping is
        // the same intent typing is — "put me at the live edge" — and a silent
        // refusal is indistinguishable from a dead feature, so the anchor
        // yields instead; the caller drops it before sending.
        let t = getTerminal()
        let line = t.getLine(row: row + t.buffer.yDisp)?
            .translateToString(trimRight: true) ?? ""
        let walk = cursorWalk(fromRow: t.buffer.y, fromCol: t.buffer.x,
                              toRow: row, toCol: col, targetLineLength: line.count)
        if walk == nil {
            // A refused walk looks exactly like a broken feature, so say why.
            walkMark("walk refused: r\(row) c\(col) from r\(t.buffer.y) c\(t.buffer.x) lineLen=\(line.count)")
        }
        return walk
    }

    private func flashTapCaret(col: Int, row: Int, cellW: CGFloat, cellH: CGFloat) {
        let caret = CALayer()
        caret.frame = CGRect(x: CGFloat(col - 1) * cellW + bounds.origin.x,
                             y: CGFloat(row - 1) * cellH + bounds.origin.y,
                             width: max(2, cellW * 0.14), height: cellH)
        caret.backgroundColor = UIColor(Color.hopGlow).cgColor
        caret.cornerRadius = 1
        layer.addSublayer(caret)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.4
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { caret.removeFromSuperlayer() }
        caret.opacity = 0            // land at 0 so it stays gone after the fade
        caret.add(fade, forKey: "fade")
        CATransaction.commit()
    }

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
        if g.state == .began { selectMark("back swipe began"); onBackSwipe?() }
    }

    /// "A single touch should trigger autofit" — the coordinator hangs the
    /// size reclaim here. Wired into touchesEnded, NOT becomeFirstResponder:
    /// SwiftTerm only calls the latter when the terminal isn't focused yet
    /// (probe-proven — an already-focused terminal swallowed the tap), while
    /// a completed touch is every tap. Pans and selections never get here —
    /// their recognizers cancel the view's touches — so READING a foreign
    /// grid by panning it stays free of claims.
    var onUserIntent: (() -> Void)?

    /// A pan gesture just began while pannable (peerSizedGrid) — carries
    /// naturalFit()'s guess of what should actually fit, in case that's
    /// disagreeing with what's pinned for reasons SwiftTerm's own layout
    /// pass hasn't had a reason to notice (see the pan-stuck bug note in
    /// handleScrollPan). The coordinator owns the decision of what to do
    /// with it — this view only reports the mismatch.
    var onPossibleSizeMismatch: ((Int, Int) -> Void)?

    weak var keyHandler: AccessoryKeyHandler?
    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var shiftButton: UIButton?
    private var cmdButton: UIButton?
    private var repeatTimer: Timer?

    /// SwiftTerm's iOS view has no scroll gesture: one pan handler forwards
    /// mouse events (claude turns mouse mode on, so drags reach the app) and
    /// the other does selection, whose only scroll-ish branch sends ARROW KEYS.
    /// Nothing moves the local viewport, so the scrollback was unreachable by
    /// touch — the first gesture anyone tries on a phone.
    ///
    /// Drags the buffer 1:1 with the finger, alongside SwiftTerm's own
    /// recognizers so long-press selection and its menu keep working.
    /// Accumulated travel since the last arrow we sent, so movement is
    /// continuous rather than one arrow per gesture.
    private var cursorPanX: CGFloat = 0
    private var cursorPanY: CGFloat = 0

    @objc private func handleCursorPan(_ g: UIPanGestureRecognizer) {
        guard let handler = keyHandler else { return }
        switch g.state {
        case .began:
            cursorPanX = 0
            cursorPanY = 0
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .changed:
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            cursorPanX += t.x
            cursorPanY += t.y
            let term = getTerminal()
            let cellW = max(6, bounds.width / CGFloat(max(1, capCols > 0 ? capCols : term.cols)))
            let cellH = drawnCellHeight(viewHeight: bounds.height,
                                        drawnRows: capRows, terminalRows: term.rows)
            // Horizontal wins outright while it dominates: a composer line is
            // what you are usually editing, and letting a few points of
            // vertical drift fire ↑ would walk you out of it into history.
            if abs(cursorPanX) >= abs(cursorPanY) {
                while abs(cursorPanX) >= cellW {
                    let right = cursorPanX > 0
                    cursorPanX -= right ? cellW : -cellW
                    handler.scrollInput(right ? "\u{1b}[C" : "\u{1b}[D")
                }
                cursorPanY = 0
            } else {
                while abs(cursorPanY) >= cellH {
                    let down = cursorPanY > 0
                    cursorPanY -= down ? cellH : -cellH
                    handler.scrollInput(down ? "\u{1b}[B" : "\u{1b}[A")
                }
                cursorPanX = 0
            }
        default:
            cursorPanX = 0
            cursorPanY = 0
        }
    }

    func installScrollGesture() {
        _ = Self.hasTextAlwaysTrue   // arm the hold-⌫ repeat fix once

        // On a phone a drag scrolls. That has to be exclusive, because
        // SwiftTerm's own pans do two things we don't want during a scroll:
        // with mouse mode on (claude turns it on) a drag sends a CLICK at the
        // start point, which in a TUI can activate whatever is under your
        // finger; with it off, the same handler sends ARROW KEYS. Neither is
        // an acceptable side effect of scrolling, so its pans are disabled and
        // mouse reporting with them.
        //
        // NOT traded away: drag-to-extend. SwiftTerm re-installs its selection
        // pan when a selection begins (select() → enableSelectionPanGesture),
        // and gestureRecognizerShouldBegin lets that one through while ours
        // yield — so the handles a long-press summons can actually be moved.
        allowMouseReporting = false
        for existing in gestureRecognizers ?? [] where existing is UIPanGestureRecognizer {
            existing.isEnabled = false
        }
        let pan = SlopPanGestureRecognizer(target: self, action: #selector(handleScrollPan))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        scrollPan = pan
        // iOS's trackpad, for a terminal. Two fingers anywhere on the screen
        // move the CURSOR instead of the viewport — the gesture iOS gives you
        // by holding the spacebar, which we cannot borrow because that belongs
        // to UITextView and a terminal has no text view. So we emit what the
        // shell understands: one arrow per cell of travel, continuously, while
        // the fingers move. Two touches exactly, so single-finger scrolling
        // and selection are untouched, and it works with the system keyboard
        // up, the hop keyboard, or none at all.
        let cursorPan = UIPanGestureRecognizer(target: self,
                                               action: #selector(handleCursorPan))
        cursorPan.minimumNumberOfTouches = 2
        cursorPan.maximumNumberOfTouches = 2
        cursorPan.delegate = self
        addGestureRecognizer(cursorPan)
        self.cursorPan = cursorPan
        // Swipe between recent sessions on the BODY, not only the pill
        // (Jian: "swipe left and right between most recent sessions when not
        // in panning mode"). Horizontal single-finger drags were unclaimed
        // until now — vertical dominance owns scrolling, pan mode owns both
        // axes — so this moves into an empty slot rather than contesting one:
        // it begins only for decisively horizontal drags, never in pan mode,
        // never during a selection, never in the chrome strip.
        let switchPan = SlopPanGestureRecognizer(target: self, action: #selector(handleSwitchPan))
        switchPan.maximumNumberOfTouches = 1
        switchPan.delegate = self
        addGestureRecognizer(switchPan)
        self.switchPan = switchPan
        // The top strip belongs to the chrome: it is where anyone reaches for
        // controls, and it is the one place a tap is not meant as "give me the
        // keyboard".
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleChromeTap))
        tap.delegate = self
        addGestureRecognizer(tap)
        chromeTap = tap
        // The escape hatch that no layout can take away: two fingers anywhere
        // summon the chrome. The strip is a position, and positions can end
        // up off screen; this one is reachable wherever the terminal happens
        // to sit, and two fingers is never a request to type.
        let twoFinger = UITapGestureRecognizer(target: self, action: #selector(handleChromeTap))
        twoFinger.numberOfTouchesRequired = 2
        twoFinger.delegate = self
        addGestureRecognizer(twoFinger)
        chromeTapTwoFinger = twoFinger
        // Taps become CLICKS for apps that asked for the mouse. #55 removed
        // phantom taps because accidental activation was the pain; the pill
        // case is the opposite — claude DRAWS click targets, and a phone
        // that can never click can never reach them (Jian: "the jump to
        // bottom button is not clickable"). Gated in shouldBegin: mouse-on
        // sessions only, below the chrome strip, never while braking a
        // coast.
        // SELECT AND COPY (Jian: "select and copy is not working — in mobile
        // web we choose between scrolling and selecting; we shouldn't have to
        // in native"). We don't: press-and-hold SELECTS (a hold is never a
        // scroll — pans need movement), dragging afterwards extends through
        // SwiftTerm's own selection pan, and our scroll pan already yields
        // while a selection is active. What was actually broken: SwiftTerm's
        // whole copy UI is UIMenuController, which modern iOS silently
        // refuses to show — the machinery worked, its face didn't. The face
        // is now UIEditMenuInteraction.
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleSelectHold))
        hold.minimumPressDuration = 0.45
        // Same drift budget as the pans' slop: a hold that fails at UIKit's
        // default 10pt dies to the fingertip settling (see SlopPan…).
        hold.allowableMovement = 18
        // Delegate = us, for the simultaneity grant: SwiftTerm installs its
        // own long-press on the same view, and without simultaneous
        // recognition exactly one of the two fires — arbitration picked
        // theirs (probe-proven: the menu never appeared).
        hold.delegate = self
        addGestureRecognizer(hold)
        selectHold = hold
        // A finger lifting after a HOLD is not a tap. Every tap recognizer on
        // this view — SwiftTerm's own single tap included, whose handler
        // clears the selection and hides the menu — fired on that release
        // (~300ms later, after the double-tap window), so in Codex the
        // selection and the native menu vanished ~250ms after they appeared
        // (trace: +150ms menu=true sel=true, +400ms both false). Taps now
        // wait for the hold to FAIL; a recognized hold means no tap.
        for gr in gestureRecognizers ?? [] where gr is UITapGestureRecognizer && gr !== hold {
            gr.require(toFail: hold)
            gr.addTarget(self, action: #selector(tapObserved(_:)))
        }

        let click = UITapGestureRecognizer(target: self, action: #selector(handleClickTap))
        click.delegate = self
        addGestureRecognizer(click)
        clickTap = click
        click.require(toFail: hold)   // created after the hold: same rule
        click.addTarget(self, action: #selector(tapObserved(_:)))
        selectMark("recognizers: " + (gestureRecognizers ?? []).map { g in
            "\(type(of: g))\(g.isEnabled ? "+" : "-")" }.joined(separator: " "))
        let back = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleBackSwipe))
        back.edges = .left
        addGestureRecognizer(back)
        // The terminal is a FIXED VIEWPORT — Jian's principle, verbatim:
        // native scrolling must never show up; the element always fits and
        // hop handles what scrolling MEANS. SwiftTerm's view is a
        // UIScrollView underneath, and even with its pans disabled UIKit
        // still had hands on it: bounce animated an end-of-content that
        // doesn't exist, keyboard changes scrolled-to-visible and adjusted
        // insets under us (the "native scroll is back" report), and the
        // indicator flashed for motion the user never asked for. All of it
        // off; programmatic offset (peer-pan, scrollTo) still works.
        bounces = false
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        isScrollEnabled = false
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
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
        if g.state == .began {
            stopMomentum()
            // A gesture is the user acting on what they SEE — the one moment
            // stale geometry is guaranteed to be noticed. Force a layout
            // pass FIRST: after a wake, drawn dims (and naturalFit, which
            // reads them) can still describe the pre-lock layout, and no
            // layout may run again for a long stretch on its own (proven,
            // device log, build 325). Then report any grid≠natural mismatch
            // — in EITHER direction: bigger than drawable was
            // pannable-not-scrollable; smaller than the fit is the
            // half-height screen (a keyboard-up grid surviving into a
            // keyboard-down view). Reported via onPossibleSizeMismatch, NOT
            // the TerminalViewDelegate — going through sizeChanged would
            // also run its drawnCols/drawnRows update for what isn't a real
            // layout measurement. The coordinator's peerHoldsSize check
            // still applies on the other end: a peer-held grid gets a
            // polite re-declare and keeps panning/letterboxing; only the
            // OURS-but-mismatched case gets re-pinned and corrected.
            setNeedsLayout()
            layoutIfNeeded()
            let t = getTerminal()
            KBLog.record("gesture began moved=\(Int(hypot(g.translation(in: self).x, g.translation(in: self).y)))pt grid=\(t.cols)x\(t.rows) drawn=\(drawnCols)x\(drawnRows) pinned=\(pinnedGrid.map { "\($0.cols)x\($0.rows)" } ?? "nil") nat=\(naturalFit().map { "\($0.cols)x\($0.rows)" } ?? "nil")")
            if let nat = naturalFit(), nat != (t.cols, t.rows) {
                onPossibleSizeMismatch?(nat.cols, nat.rows)
            }
        }
        if !peerSizedGrid { panExtra = .zero }
        if peerSizedGrid {
            // Panning, not scrolling: the content moves with the finger, both
            // axes, and momentum carries it — the grid is a surface here.
            switch g.state {
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
            // stopMomentum already ran in the unified .began above.
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
                                   drawnRows: capRows, terminalRows: terminal.rows)
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
    /// While a peer holds the size, the local terminal is PINNED to the PTY's
    /// grid. SwiftTerm re-fits the terminal to the view on every bounds
    /// change (layoutSubviews → processSizeChange, internal, not
    /// overridable) and on every font change (resetFont) — each refit
    /// re-wraps the buffer at the local width and the snap-back re-wraps it
    /// again, and SwiftTerm's rewrap of styled/wrapped lines is where "two
    /// lines of text show in one, randomly interspersed" comes from (Jian,
    /// three reports — visible on every keyboard frame or refresh). The pin
    /// corrects INSIDE the same layout pass, before a frame is drawn at the
    /// wrong grid; with the font scaled to the elected columns the wrong fit
    /// differs only in ROWS, and row-only resizes do not rewrap.
    var pinnedGrid: (cols: Int, rows: Int)?

    /// iOS auto-repeats a held delete key ONLY while the responder reports
    /// hasText — and SwiftTerm computes it from its synthetic UITextInput
    /// storage, which our reconnect/reset churn empties. Storage empty → iOS
    /// decides there is nothing to delete → hold-⌫ stops repeating. A
    /// terminal ALWAYS conceptually has text before the cursor, and
    /// SwiftTerm's deleteBackward handles empty storage by sending a raw
    /// backspace — so answering true is honest AND restores the repeat.
    /// hasText is public-not-open, so a Swift override is refused; UIKit
    /// reads it through the ObjC runtime, and the runtime can answer.
    /// Scoped to THIS subclass only.
    static let hasTextAlwaysTrue: Void = {
        let sel = #selector(getter: UIKeyInput.hasText)
        let imp = imp_implementationWithBlock({ (_: AnyObject) -> Bool in true } as @convention(block) (AnyObject) -> Bool)
        if let method = class_getInstanceMethod(HopTermView.self, sel) {
            class_replaceMethod(HopTermView.self, sel, imp,
                                method_getTypeEncoding(method))
        }
    }()

    /// The font the USER chose, independent of auto-scale. What a keystroke
    /// claims must be computed from this: while a peer's grid is drawn, the
    /// live fittedCols/Rows describe the SCALED font, and claiming those
    /// would "take" the peer's own size — a keystroke that changes nothing.
    var naturalFontPt: CGFloat = 12
    /// MEASURED, not modeled (device log, build 325): the analytic guess —
    /// advance width of "0" and UIFont.lineHeight — runs smaller than
    /// SwiftTerm's real cell metrics, so it OVERESTIMATED the fit
    /// (claimed 80x50 where SwiftTerm draws 79x48). Every attach then
    /// claimed a grid bigger than drawable, the server confirmed it as
    /// ours, the pin held it, and the session sat pannable-not-scrollable
    /// with no chip — while every self-heal that compared against the same
    /// analytic number concluded nothing was wrong. SwiftTerm's own fit
    /// (drawnCols/Rows, pushed in from sizeChanged) is ground truth for
    /// what draws; the analytic path survives only as the pre-first-layout
    /// fallback, when there is no measurement yet to trust.
    /// The natural fit measured STRAIGHT from the font + current bounds — no
    /// dependence on any drawn grid. The ground truth for "what fits at the
    /// natural font here"; slightly less exact than SwiftTerm's own cell (a
    /// few columns), so it is the fallback, not the default.
    /// SwiftTerm's OWN cell recipe (AppleTerminalView.computeFontDimensions),
    /// reproduced exactly: width of "W", height = ceil(ascent + descent +
    /// leading) × lineSpacing, both snapped UP to the pixel grid. The old
    /// estimate ("0" width, UIFont.lineHeight, unsnapped) came out ~2 cols and
    /// ~2 rows bigger than what SwiftTerm actually fits — so a phone returning
    /// from a foreign grid claimed 58x34, the PTY took it, and the terminal
    /// drew 56x32: last two columns and rows cut off (diagnostic 2026-10-03,
    /// "fit MISMATCH pinned=58x34 natural=56x32").
    static func cellSize(fontPt: CGFloat, lineSpacing: CGFloat) -> CGSize {
        let f = UIFont.monospacedSystemFont(ofSize: fontPt, weight: .regular)
        let w = ("W" as NSString).size(withAttributes: [.font: f]).width
        let h = ceil((f.ascender - f.descender + f.leading) * lineSpacing)
        let scale = UIScreen.main.scale
        return CGSize(width: max(1, ceil(w * scale) / scale), height: max(1, ceil(h * scale) / scale))
    }

    private func directFit() -> (cols: Int, rows: Int)? {
        let cell = Self.cellSize(fontPt: naturalFontPt, lineSpacing: lineSpacing)
        guard cell.width > 1, cell.height > 1 else { return nil }
        return (max(2, Int(bounds.width / cell.width)), max(2, Int(bounds.height / cell.height)))
    }

    func naturalFit() -> (cols: Int, rows: Int)? {
        guard bounds.width > 10, bounds.height > 10 else { return nil }
        let measuredFont = drawnFontPt > 0.1 ? drawnFontPt : font.pointSize
        // The drawn grid is a trustworthy stand-in for the natural fit ONLY
        // when it was measured at ~the natural font — i.e. it is a real
        // bounds-fit. When the font is far from natural, it is not: we shrank
        // the font to ADOPT A FOREIGN grid, whose columns fill the width but
        // whose ROWS are letterboxed (not a fit). Rescaling that by the font
        // ratio produced a bogus short claim — trace-convicted: 184x48 drawn
        // at 4pt rescaled to 73x19 at 10pt, half the height, then confirmed as
        // OURS. Off-natural → ignore the drawn grid and measure directly.
        // (Also covers the Aug-18 transient-large-font case: direct is correct
        // there too, so it no longer needs the drawn-rescale it once relied on.)
        if drawnCols > 1, drawnRows > 1, abs(measuredFont - naturalFontPt) <= 2.5 {
            // Through scaledFit: the drawn numbers are only exact for the
            // bounds they were measured in, and sizeChanged does not fire
            // again when a bounds change lands back on the grid the terminal
            // already has. The measured cell scaled to current bounds rounds
            // DOWN at worst — letterbox, never an undrawable claim.
            let scaled = abs(measuredFont - naturalFontPt) < 0.1
                ? 1 : naturalFontPt / measuredFont
            let byDrawn = scaledFit(bounds: bounds.size, measuredAt: drawnBounds,
                                    drawnCols: drawnCols, drawnRows: drawnRows,
                                    fontRatio: scaled)
            // Self-heal an ALREADY mis-settled grid: if a bogus short claim was
            // confirmed as ours (e.g. that 73x19) the drawn grid now trusts
            // itself at the natural font, so nothing above ever corrects it.
            // The direct fit is measured from the font, not the lie — if it
            // says the bounds hold FAR more rows than the drawn grid shows,
            // the drawn grid is the stale liar. Only a large gap (letterbox,
            // never rounding) and only when we could own the grid (natural
            // font ⇒ not observing a shrunk foreign grid). A peer-held
            // declaration reads direct too, which is the honest natural fit
            // and never moves the PTY.
            if let byDrawn, let direct = directFit(),
               byDrawn.rows < Int(Double(direct.rows) * 0.7) {
                // Throttled: naturalFit is read many times a second during a
                // gesture, and an unthrottled heal log floods the diagnostic
                // ring so a later trace loses all earlier context.
                healLog("naturalFit heal: drawn \(byDrawn.cols)x\(byDrawn.rows) << direct "
                    + "\(direct.cols)x\(direct.rows) at natural font — taking direct")
                return direct
            }
            return byDrawn
        }
        if drawnCols > 1, drawnRows > 1 {
            healLog("naturalFit direct (drawn \(drawnCols)x\(drawnRows) @ \(String(format: "%.1f", measuredFont))pt off-natural \(Int(naturalFontPt)) — not a bounds-fit)")
        }
        return directFit()
    }

    private var lastHealLogAt = Date.distantPast
    /// KBLog, but at most once every 2s — for the fit-heal messages that fire
    /// on every gesture frame while a grid is mis-settled.
    private func healLog(_ msg: String) {
        guard Date().timeIntervalSince(lastHealLogAt) > 2 else { return }
        lastHealLogAt = Date()
        KBLog.record(msg)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let pin = pinnedGrid else { return }
        let t = getTerminal()
        if t.cols != pin.cols || t.rows != pin.rows {
            walkMark("local resize → \(pin.cols)x\(pin.rows)")
            t.resize(cols: pin.cols, rows: pin.rows)
            t.updateFullScreen()
            setNeedsDisplay(bounds)
            scheduleSettleRedraw("layout-pin")
        }
        applyLetterbox()
    }

    /// One more full repaint after the dust settles. The CoreGraphics
    /// renderer draws rows from contentOffset and cell metrics, and font
    /// changes, grid pins, snapshot replays and keyboard moves all shift
    /// those under an in-flight draw — a draw that raced one can leave
    /// garbled/overlapping rows sitting in the backing store, and a QUIET
    /// session never repaints them (no output, no redraw), which is why the
    /// artifact survives until a scroll forces exactly this pass (Jian:
    /// "overlapping text ... scrolling fix it"). Every churn point schedules
    /// one; the debounce means only the last survivor of a burst runs, and
    /// one extra repaint of a settled screen costs nothing visible.
    private var settleRedraw: DispatchWorkItem?
    func scheduleSettleRedraw(_ reason: String) {
        settleRedraw?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil else { return }
            let t = self.getTerminal()
            let before = Int(self.contentOffset.y)
            // Re-assert the PTY grid first: everything below renders what the
            // terminal currently is, so a drifted row count would just be
            // repainted faithfully. layoutSubviews does this too, but only
            // when a layout pass happens to run — and the states worth
            // healing are exactly the ones where nothing triggers one.
            var regrid = ""
            if let pin = self.pinnedGrid, t.cols != pin.cols || t.rows != pin.rows {
                regrid = " regrid=\(t.cols)x\(t.rows)→\(pin.cols)x\(pin.rows)"
                walkMark("local resize → \(pin.cols)x\(pin.rows)")
                t.resize(cols: pin.cols, rows: pin.rows)
            }
            self.resyncViewport()
            t.updateFullScreen()
            self.setNeedsDisplay(self.bounds)
            self.applyLetterbox()
            KBLog.record("settle redraw (\(reason)) grid=\(t.cols)x\(t.rows) "
                + "drawn=\(self.drawnCols)x\(self.drawnRows) off=\(before)→\(Int(self.contentOffset.y)) "
                + "font=\(String(format: "%.1f", self.font.pointSize))\(regrid)")
        }
        settleRedraw = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Put contentOffset back into CURRENT cell units. The renderer picks
    /// which rows to draw from contentOffset / cellHeight at draw time; a
    /// font rescale changes cellHeight and leaves the offset in OLD units,
    /// so every repaint faithfully paints the WRONG PAGE of the buffer —
    /// whole pages mixed on screen, not a stray line (Jian: "the previous
    /// page was not completely cleaned or two pages got written the same
    /// time"). SwiftTerm's own resync (updateScroller) runs only on feeds,
    /// and a quiet session feeds nothing — which is why only a scroll ever
    /// healed it. scrollTo to the row we are ALREADY on is the public
    /// spelling of that resync: same content row, offset recomputed in the
    /// current cell metrics. Skipped while a finger or momentum owns the
    /// offset, and in pan mode, where contentOffset IS the pan position.
    func resyncViewport() {
        guard !isTracking, !isDecelerating, !peerSizedGrid else { return }
        scrollTo(row: getTerminal().buffer.yDisp, notifyAccessibility: false)
    }

    /// Centre a grid that cannot fill this screen.
    ///
    /// A desk grid is wide and short (80x24 is about 3.3:1); a phone is tall
    /// and narrow (about 0.5:1). Shrinking the font until 80 columns fit the
    /// width leaves 24 tiny rows covering roughly HALF the height — that is
    /// geometry, not a bug, and no claim policy can dissolve it while we are
    /// honouring someone else's grid. What we can fix is where the slack
    /// goes: hung from the top it reads as "the bottom half is broken"
    /// (Jian: "still shows half height"); split evenly it reads as a screen
    /// of a different shape, deliberately letterboxed.
    ///
    /// A TRANSFORM, not a frame change: bounds stay the full screen, so
    /// SwiftTerm keeps fitting to the real viewport and the size we would
    /// claim on your next keystroke is still YOUR size, not the letterbox's.
    /// Getting that wrong would make typing claim the peer's grid forever.
    /// How many points of this view's top the floating menu covers. Zero
    /// while the menu is hidden (auto-hide, landscape) — nothing is covering
    /// anything then, and the full height is honestly usable.
    var chromeOverlap: CGFloat = 0 {
        didSet { if chromeOverlap != oldValue { applyLetterbox() } }
    }
    private var lastLoggedShift: CGFloat = -1

    /// How far to push content down so the LIVE text clears the menu.
    ///
    /// Jian's rule: the covered band is an overflow area, not reserved space
    /// — "we always scroll the terminal so that the current line is below the
    /// menu". Reserving it in the frame instead would have cost four rows off
    /// the PTY forever, which is the wrong trade for a band that is only in
    /// the way when a session is nearly empty.
    ///
    /// So HISTORY pays for the band first: a line that has already scrolled
    /// off the top is exactly the kind of line that should sit behind a menu,
    /// and every point of scrollback buys back a point of shift. A brand new
    /// session has none, so it is pushed fully clear — which is the reported
    /// bug, a fresh shell prompt drawn underneath the bar. A long-running one
    /// has plenty and uses every point of the screen.
    ///
    /// Two things this must never do. It must not push the live line off the
    /// BOTTOM to clear the top, so the shift is also capped by the room left
    /// below the cursor — as the cursor approaches the last row the content
    /// slides up to meet it, which reads as the screen scrolling. And it does
    /// nothing on the alternate screen, where a full-screen app owns every
    /// row and draws its own composer at the bottom: there is no scrollback
    /// to pay with, and shifting would hide the very line being typed into.
    private func chromeShift() -> CGFloat {
        guard chromeOverlap > 0, !remoteAltScreen else { return 0 }
        let t = getTerminal()
        // Only a grid too TALL to draw blocks this, not `peerSizedGrid`:
        // that reads true when a peer's grid is merely too WIDE, which is the
        // common shape (a desk's 80 columns on a phone that draws 51) and
        // leaves plenty of vertical room. Guarding on it skipped the shift
        // for exactly the session this was reported against — device log:
        // rows=24 drawn=32 cols=80, vertically roomy, horizontally not.
        guard capRows <= 0 || t.rows <= capRows else { return 0 }
        let unpaid = chromeOverlap - max(0, contentSize.height - bounds.height)
        guard unpaid > 0 else { return 0 }
        let cell = drawnCellHeight(viewHeight: bounds.height,
                                   drawnRows: capRows, terminalRows: t.rows)
        let roomBelowCursor = CGFloat(max(0, t.rows - 1 - t.buffer.y)) * cell
        return max(0, min(unpaid, roomBelowCursor))
    }

    func applyLetterbox() {
        let rows = getTerminal().rows
        let capacity = capRows > 0 ? capRows : rows
        guard capacity > 0, rows > 0, bounds.height > 1 else { return }
        let dy = letterboxOffset(viewHeight: bounds.height,
                                 gridRows: rows, capacityRows: capacity)
        // Whichever is further down wins rather than the sum: letterboxing
        // already centres a short grid, and stacking a second offset on top
        // of that would push it off the bottom of the screen.
        let shift = max(dy, chromeShift())
        // Into the same ring the size traces use: the shift depends on three
        // moving numbers, and "why is the top row where it is" is otherwise
        // unanswerable from a device.
        if shift != lastLoggedShift {
            lastLoggedShift = shift
            KBLog.record("chrome shift \(Int(shift)) (letterbox \(Int(dy)), overlap "
                + "\(Int(chromeOverlap))) grid=\(getTerminal().cols)x\(getTerminal().rows) "
                + "drawn=\(drawnCols)x\(drawnRows) scrollback="
                + "\(Int(max(0, contentSize.height - bounds.height)))")
        }
        let wanted = shift > 0 ? CGAffineTransform(translationX: 0, y: shift) : .identity
        if transform != wanted { transform = wanted }
    }
    var drawnCols = 0
    /// The bounds drawnCols/drawnRows were measured IN — stale drawn numbers
    /// read against new bounds are how the settle check once re-claimed half
    /// a screen (Accessibility-fork trace, 2026-08-14).
    var drawnBounds: CGSize = .zero
    /// The FONT the measurement was taken at — the second half of the same
    /// staleness (2026-08-18 trace). naturalFit rescales by the ratio of the
    /// natural font to THIS, not to the live font, so a 64x19 measured at a
    /// transient large font correctly reads as ~40 rows at natural size.
    var drawnFontPt: CGFloat = 0

    /// What the CURRENT bounds can draw — every geometry decision reads
    /// THIS, never drawnCols/drawnRows raw. The day after the half-screen
    /// fix, the same stale record broke scrolling instead (Europa trace:
    /// grid 62x46, drawn 62x28): peerSizedGrid compared the healthy grid
    /// against a measurement from a 344pt viewport, read "too big to draw",
    /// and PAN MODE swallowed the wheel gestures claude should have gotten.
    /// No font ratio here: a font change re-fits and refreshes the
    /// measurement, so the cell is current by construction.
    private var measuredFontRatio: CGFloat {
        let measuredFont = drawnFontPt > 0.1 ? drawnFontPt : font.pointSize
        return abs(measuredFont - naturalFontPt) < 0.1 ? 1 : naturalFontPt / measuredFont
    }
    /// The grid the CURRENT bounds+font can draw — the geometry door for the
    /// pan verdict, letterbox and cell math. Normally SwiftTerm's own measured
    /// cell (scaledFit of drawn), which is exact. But `drawn` can go stale or
    /// corrupt across a font storm: trace-convicted, drawn settled at 80x25
    /// tagged font 10 — physically impossible in 398pt (80 cols needs a 5pt
    /// cell) — so capRows read 25 for a real 38-row grid and peerSizedGrid put
    /// a scroll into PAN mode. So: at the NATURAL font, where the true capacity
    /// IS the font-metric fit, a drawn measurement wildly off that fit is the
    /// liar — take the direct fit. Off natural (observer's shrunk font) the
    /// scaled cell is exactly what we render, and direct would be wrong.
    private func drawableCap() -> (cols: Int, rows: Int)? {
        let byDrawn = scaledFit(bounds: bounds.size, measuredAt: drawnBounds,
                                drawnCols: drawnCols, drawnRows: drawnRows,
                                fontRatio: measuredFontRatio)
        let measuredFont = drawnFontPt > 0.1 ? drawnFontPt : font.pointSize
        guard let byDrawn else { return directFit() }
        guard abs(measuredFont - naturalFontPt) <= 2.5, let d = directFit() else { return byDrawn }
        let off = { (a: Int, b: Int) in a < Int(Double(b) * 0.7) || a > Int(Double(b) * 1.4) }
        return (off(byDrawn.rows, d.rows) || off(byDrawn.cols, d.cols)) ? d : byDrawn
    }
    var capCols: Int { drawableCap()?.cols ?? drawnCols }
    var capRows: Int { drawableCap()?.rows ?? drawnRows }

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
        if getTerminal().buffer.yDisp != anchor {
            selectMark("restore anchor \(anchor) from yDisp=\(getTerminal().buffer.yDisp)")
            scrollTo(row: anchor)
        }
        return true
    }

    /// A peer owns the PTY size and the grid is bigger than this view can
    /// draw. In this state a drag PANS over the full grid, 1:1 with the
    /// finger — the same behaviour as hop's mobile web. Scroll-as-wheel and
    /// scrollback come back the moment the grid fits again.
    var peerSizedGrid: Bool {
        guard drawnRows > 0, drawnCols > 0 else { return false }
        let capC = capCols, capR = capRows
        let t = getTerminal()
        return t.rows > capR || t.cols > capC
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
        let cellW = bounds.width / CGFloat(capCols)
        let cellH = drawnCellHeight(viewHeight: bounds.height,
                                    drawnRows: capRows, terminalRows: t.rows)
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
                                   drawnRows: capRows, terminalRows: getTerminal().rows)
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
    var remoteTakesMouse: Bool { remote.takesWheel }
    private var sink: ScrollSink {
        scrollSink(altScreen: remote.altScreen, takesWheel: remote.takesWheel)
    }

    func setRemoteModes(altScreen: Bool, mouseReporting: Bool, mouseSgr: Bool) {
        remote.seed(altScreen: altScreen, mouseReporting: mouseReporting, mouseSgr: mouseSgr)
    }

    func noteRemoteModes(in chunk: String) { remote.note(chunk) }

    /// Set from the session list on every update — the same signal the wall's
    /// app chips render. The FALLBACK gate for shift+enter, mirroring hop
    /// web's foregroundIsClaude(): claude parses CSI-u unconditionally but
    /// (since ~July 2026 builds) no longer advertises the protocol at boot,
    /// so waiting for the enable would never fire.
    var runningAppName = ""

    /// What ⇧⏎ puts on the wire RIGHT NOW. Encoded when the app negotiated
    /// enhanced keys or is claude; a plain enter otherwise, because raw CSI-u
    /// in a shell renders as junk text — same gate, same reasons, as the web.
    func shiftEnterSequence() -> String {
        if remote.kbdEnhanced || runningAppName.localizedCaseInsensitiveContains("claude") {
            return "\u{1b}[13;2u"
        }
        return "\r"
    }

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
    /// Whether this runs before or after the recognizers are asked depends on
    /// whether the scroll view is delaying touch delivery (isScrollEnabled
    /// changes that), so the brake can't be inferred from momentumLink alone —
    /// this latch marks the touch that killed the coast as "the brake", and
    /// gestureRecognizerShouldBegin refuses taps while it's fresh. It's a
    /// TIMESTAMP, not a flag: a brake is a moment, and if the end of its
    /// touch is never delivered (recognizer arbitration under load), a stale
    /// latch must not eat the next honest tap.
    private var brakeTouchAt: CFTimeInterval = -1
    private var brakeTouch: Bool { CACurrentMediaTime() - brakeTouchAt < 0.8 }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { let l = t.location(in: self); selectMark("touch began x=\(Int(l.x - bounds.origin.x)) y=\(Int(l.y - bounds.origin.y))") }
        if momentumLink != nil {
            stopMomentum()
            brakeTouchAt = CACurrentMediaTime()
        }
        super.touchesBegan(touches, with: event)
    }
    // The up-event reaches the recognizers (and their shouldBegin) before the
    // view, so clearing here still leaves the braking tap refused — while the
    // NEXT tap starts clean.
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        brakeTouchAt = -1
        logTouchVerdict("ended", touches)
        super.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        brakeTouchAt = -1
        logTouchVerdict("cancelled", touches)
        super.touchesCancelled(touches, with: event)
    }
    /// Who won a touch: the hold's state plus every recognizer that got past
    /// .possible. One line per touch, device-visible via Send diagnostics.
    private func logTouchVerdict(_ how: String, _ touches: Set<UITouch>) {
        let held = touches.first.map { CACurrentMediaTime() - $0.timestamp } ?? 0
        let name: (UIGestureRecognizer) -> String = { [unowned self] g in
            if g === self.selectHold { return "hold" }
            if g === self.scrollPan { return "scroll" }
            if g === self.cursorPan { return "cursor" }
            if g === self.switchPan { return "switch" }
            if g === self.clickTap { return "click" }
            return String(describing: type(of: g))
        }
        let states = (gestureRecognizers ?? []).compactMap { g -> String? in
            switch g.state {
            case .possible: return nil
            case .began: return "\(name(g))=began"
            case .changed: return "\(name(g))=changed"
            case .ended: return "\(name(g))=ended"
            case .cancelled: return "\(name(g))=cancelled"
            case .failed: return g === selectHold ? "hold=failed" : nil
            @unknown default: return nil
            }
        }
        KBLog.record("touch \(how) after \(Int(held * 1000))ms hold=\(selectHold.map { "\($0.state.rawValue)" } ?? "nil") en=\(selectHold?.isEnabled ?? false) sel=\(selectionActive) mouse=\(remoteTakesMouse) alt=\(remoteAltScreen) [\(states.joined(separator: " "))]")
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

    /// Frame-gap instrument (PLAN 26): a permanent, near-free measurement
    /// of main-thread stalls while a terminal is open. The momentum code
    /// has long SUSPECTED parse-burst stalls (its elapsed clamp exists for
    /// them); this records them, with the feed sizes beside them in the
    /// same KBLog ring, so Copy diagnostics answers whether output bursts
    /// actually drop frames — the coalescing fix is built only if they do.
    private var frameGapLink: CADisplayLink?
    private var lastGapRecordAt: CFTimeInterval = 0

    func startFrameGapMonitor() {
        guard frameGapLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frameGapTick(_:)))
        link.add(to: .main, forMode: .common)
        frameGapLink = link
    }

    func stopFrameGapMonitor() {
        frameGapLink?.invalidate()
        frameGapLink = nil
    }

    @objc private func frameGapTick(_ link: CADisplayLink) {
        // duration is one frame at the display's rate; a tick arriving 3+
        // frames late (and >50ms) is a real stall, not scheduler jitter.
        let expected = link.duration > 0 ? link.duration : 1.0 / 60
        let gap = link.timestamp - lastFrameAt
        if lastFrameAt > 0, gap > max(0.05, expected * 3),
           link.timestamp - lastGapRecordAt > 0.25 {
            lastGapRecordAt = link.timestamp
            KBLog.record("frameGap \(Int(gap * 1000))ms")
        }
        lastFrameAt = link.timestamp
    }
    private var lastFrameAt: CFTimeInterval = 0

    private var selectHold: UILongPressGestureRecognizer?
    private var scrollPan: UIPanGestureRecognizer?
    /// Kept so the selection-time yield below can tell OUR pans from
    /// SwiftTerm's — identity is the only honest test there.
    private var cursorPan: UIPanGestureRecognizer?
    private var switchPan: UIPanGestureRecognizer?

    /// The body swipe's report to SwiftUI, which owns the peek pill and the
    /// actual switch. dx is raw finger travel; the callback shapes it.
    enum SwipePhase { case moved, commit, cancel }
    var onSessionSwipe: ((SwipePhase, CGFloat) -> Void)?

    @objc private func handleSwitchPan(_ g: UIPanGestureRecognizer) {
        let dx = g.translation(in: self).x
        switch g.state {
        case .changed:
            onSessionSwipe?(.moved, dx)
        case .ended:
            // Every release is a release: the lit card decides whether it
            // switches (see switchDragEnded). Distance and velocity gates
            // could veto a switch the filmstrip had already armed.
            onSessionSwipe?(.commit, dx)
        case .cancelled, .failed:
            onSessionSwipe?(.cancel, dx)
        default: break
        }
    }

    private var selectHoldPoint: CGPoint = .zero
    private var keyboardWasUpAtHold = true
    /// A hold that began ON an existing selection is a handle grab until
    /// proven otherwise; if the finger then moves, the pan owns the gesture.
    private var hadSelectionAtHold = false
    private var holdMoved = false

    private var holdCell: (screenRow: Int, col: Int, yDisp: Int)?

    /// Select the word under the held cell (SwiftTerm's word rules: letters,
    /// digits, `.` `_` `-`), at its true buffer row. A press on blank selects
    /// nothing rather than a stray range.
    private func selectWordAtHoldCell() {
        guard let h = holdCell else { return }
        let t = getTerminal()
        guard let line = t.getLine(row: h.screenRow + (h.yDisp - t.buffer.yDisp))?
            .translateToString(trimRight: false) else { return }
        let chars = Array(line)
        guard h.col >= 0, h.col < chars.count else { clearSelection(); return }
        let isWord: (Character) -> Bool = { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
        guard isWord(chars[h.col]) else { clearSelection(); return }
        var left = h.col, right = h.col
        while left > 0, isWord(chars[left - 1]) { left -= 1 }
        while right < chars.count, isWord(chars[right]) { right += 1 }
        let row = h.screenRow + h.yDisp
        setSelectionRange(start: Position(col: left, row: row), end: Position(col: right, row: row))
        selectMark("hold word r\(row) c\(left)..<\(right) yDisp=\(h.yDisp) \"\(String(chars[left..<right]))\"")
    }

    @objc private func handleSelectHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            stopMomentum()
            // If the keyboard is about to RISE (we weren't first responder),
            // the layout will churn for ~0.7s — the menu must outwait it or
            // the tap lands in a moved world (probe-traced: sizeChanged
            // right after present, action never fired).
            keyboardWasUpAtHold = isFirstResponder
            hadSelectionAtHold = selectionActive
            holdMoved = false
            _ = becomeFirstResponder()
            selectHoldPoint = g.location(in: self)
            // The pressed cell in BUFFER coordinates, by hop's own mapping:
            // SwiftTerm derives the row from the raw contentOffset, which in
            // hop's managed viewport disagrees with the scrollback position
            // — so in a scrolled plain shell the word it picked was rows
            // away (a zero-width sliver; "long-press select works in Claude
            // Code but not in a regular terminal"). Alt-screen apps have no
            // scrollback, which is why Claude was fine.
            if let c = cellAt(selectHoldPoint) {
                holdCell = (screenRow: c.row, col: c.col, yDisp: getTerminal().buffer.yDisp)
            } else {
                holdCell = nil
            }
            // SwiftTerm's own long-press records the pressed cell
            // (lastLongSelect). NOTHING may mutate the recognizer set here:
            // select() adds the selection pan, and adding a recognizer
            // mid-touch RESETS this hold — .ended never arrives
            // (probe-proven: first press lost its up-event every time).
            if responds(to: NSSelectorFromString("longPress:")) {
                perform(NSSelectorFromString("longPress:"), with: g)
            }
            selectMark("hold-began")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            // allowableMovement only gates RECOGNITION; after it the hold
            // rides along with a drag. Note the drag so the release below
            // doesn't undo it.
            let p = g.location(in: self)
            if hypot(p.x - selectHoldPoint.x, p.y - selectHoldPoint.y) > 12 { holdMoved = true }
        case .ended, .cancelled:
            // Finger up: NOW select the word (the pan it installs can't hurt
            // a finished gesture). SwiftTerm's select() re-presents the
            // native menu at the selection; our Copy in it (buildMenu) reads
            // the snapshot taken here.
            // The release of a hold that GRABBED A HANDLE (a selection was
            // live, and the finger moved) must not re-select the word under
            // the original press — that replaced the whole range, so
            // adjusting one handle threw away the other's adjustment (Jian:
            // "adjusting left handle resets right handle immediately").
            // The pan already extended the selection; just capture it.
            if hadSelectionAtHold && holdMoved {
                selectMark("hold-ended on handle drag: keeping the pan's selection")
            } else {
                select(nil)              // SwiftTerm: menu + selection pan
                selectWordAtHoldCell()   // …and the RIGHT word
            }
            selectMark("hold-ended sel=\(selectionActive)")
            guard selectionActive else { return }
            captureSelection()
            if !keyboardWasUpAtHold { reshowNativeMenuAfterSettle() }
            selectMark("after-hold alt=\(remoteAltScreen) mouse=\(remoteTakesMouse) captured=\(capturedSelection?.count ?? 0)")
            for ms in [150, 400, 800, 1500, 2500] {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
                    guard let self else { return }
                    self.selectMark("+\(ms)ms menu=\(UIMenuController.shared.isMenuVisible) sel=\(self.selectionActive) yDisp=\(self.getTerminal().buffer.yDisp) off=\(Int(self.contentOffset.y))")
                }
            }
            // Re-offer after SwiftTerm's selection pan extends the range.
            let pans = (gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer }
            selectMark("pans at hold-end: " + pans.map {
                "\($0 === scrollPan ? "scroll" : $0 === cursorPan ? "cursor" : "other")\($0.isEnabled ? "+" : "-")"
            }.joined(separator: " "))
            for gr in gestureRecognizers ?? [] where gr is UIPanGestureRecognizer {
                if gr !== scrollPan, gr.isEnabled, gr.view === self,
                   !(gr is UIScreenEdgePanGestureRecognizer) {
                    gr.removeTarget(self, action: #selector(selectionPanChanged(_:)))
                    gr.addTarget(self, action: #selector(selectionPanChanged(_:)))
                }
            }
        default: break
        }
    }

    /// A trace that survives on DEVICE. `selectMark` is DEBUG-only and needs
    /// HOP_SELECT_MARKER set, so it says nothing in Jian's hands; KBLog is the
    /// ring "Send diagnostics" uploads. Walk traces go to both: tests read the
    /// marker file, the phone reports the ring. Two fixes shipped blind for
    /// want of this.
    func walkMark(_ line: String) {
        selectMark(line)
        KBLog.record(line)
    }

    func selectMark(_ line: String) {
        // ALSO on device, into the diagnostics ring: selection bugs only
        // reproduce under a real finger (2026-09-27, "long press no longer
        // triggers the system selector" — green in every simulator probe).
        // The +Nms follow-ups and resize echoes are the noisy part; keep the
        // transitions.
        if !line.hasPrefix("+"), !line.hasPrefix("active_size"), !line.hasPrefix("local resize") {
            KBLog.record("sel: " + line)
        }
        #if DEBUG
        if let m = ProcessInfo.processInfo.environment["HOP_SELECT_MARKER"] {
            let prev = (try? String(contentsOfFile: m, encoding: .utf8)) ?? ""
            try? (prev + line + "\n").write(toFile: m, atomically: true, encoding: .utf8)
        }
        #endif
    }

    @objc private func selectionPanChanged(_ g: UIPanGestureRecognizer) {
        // .changed spams ~50 lines a drag; transitions are the story.
        if g.state != .changed { selectMark("selPan state=\(g.state.rawValue) sel=\(selectionActive)") }
        guard g.state == .ended, selectionActive else { return }
        captureSelection()
    }

    /// THE NATIVE EDIT MENU, with a Copy that works. SwiftTerm's long-press
    /// presents the system menu (UIMenuController.showMenu, bridged to the
    /// edit menu on iOS 16+): Paste / Select / Select All at the finger,
    /// native styling, native placement. Its own Copy was the unreliable
    /// part — gated on `selection.active` when the menu is built, and
    /// copying the LIVE selection at tap time, while the selection gets
    /// cleared under the menu (keyboard churn, the session repainting):
    /// tap Copy, get nothing. That is why a hop chip once replaced the
    /// whole menu, and why Jian then missed Paste. Now the menu keeps every
    /// native item except that Copy and gets ours in front: ungated, and
    /// it copies the snapshot `captureSelection()` took the moment the word
    /// was selected (Jian: "if you can use a native copy and it will
    /// function correctly, it will be the best"). The bridged menu is built
    /// through UIMenuSystem.context; this responder hook decides its items.
    private var capturedSelection: String?

    private func captureSelection() {
        if let text = getSelection(), !text.isEmpty { capturedSelection = text }
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .context else { return }
        // Drop the native Copy (ours replaces it) and Select (the hold
        // already selected the word under the finger — screenshot showed it
        // beside a live selection). Paste and Select All stay native.
        if builder.menu(for: .standardEdit) != nil {
            let dropped: [Selector] = [#selector(UIResponderStandardEditActions.copy(_:)),
                                       #selector(UIResponderStandardEditActions.select(_:))]
            builder.replaceChildren(ofMenu: .standardEdit) { children in
                children.filter { child in
                    guard let action = (child as? UICommand)?.action else { return true }
                    return !dropped.contains(action)
                }
            }
        }
        guard builder.menu(for: .root) != nil else { return }
        let copy = UIAction(title: "Copy") { [weak self] _ in self?.copyCaptured() }
        builder.insertChild(UIMenu(options: .displayInline, children: [copy]),
                            atStartOfMenu: .root)
    }

    private func copyCaptured() {
        // The snapshot first; the live selection only when there is none
        // (a selection made some way the hold didn't see).
        let raw = capturedSelection ?? getSelection() ?? ""
        // A link selected while it was broken across rows pastes as a dead
        // link unless the layout comes back out; anything that isn't exactly
        // one URL is copied verbatim.
        let text = rejoinWrappedURL(raw) ?? raw
        guard !text.isEmpty else { return }
        UIPasteboard.general.string = text
        selectMark("native-copied \(text.count) chars")
        #if DEBUG
        if let marker = ProcessInfo.processInfo.environment["HOP_COPY_MARKER"] {
            try? text.write(toFile: marker, atomically: true, encoding: .utf8)
        }
        #endif
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The keyboard-was-down path: becoming first responder at hold-began
    /// raises the keyboard, and that layout churn dismisses the menu
    /// SwiftTerm presented — and the one its select() re-presents on
    /// finger-up lands mid-animation. Present it once more when still.
    private func reshowNativeMenuAfterSettle() {
        let at = selectHoldPoint
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.capturedSelection != nil else { return }
            UIMenuController.shared.showMenu(from: self,
                                             rect: CGRect(x: at.x, y: at.y, width: 1, height: 1))
        }
    }

    /// The hop keyboard. Sticky across sessions and launches: a keyboard
    /// choice is a preference, not a per-terminal mood.
    private var hopBoard: HopBoardView?
    static var hopBoardPreferred: Bool {
        get { UserDefaults.standard.bool(forKey: "hopBoard") }
        set { UserDefaults.standard.set(newValue, forKey: "hopBoard") }
    }

    /// An accessory arrow consumed the hop keyboard's one-shot ⇧.
    func clearBoardShift() { hopBoard?.clearShift() }

    func toggleHopBoard() {
        Self.hopBoardPreferred.toggle()
        applyBoardPreference()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func applyBoardPreference() {
        if Self.hopBoardPreferred {
            if hopBoard == nil {
                let board = HopBoardView()
                board.onText = { [weak self] t in self?.keyHandler?.typedText(t) }
                board.onSystemKeyboard = { [weak self] in self?.toggleHopBoard() }
                board.onShift = { [weak self] on in self?.keyHandler?.setShiftArmed(on) }
                hopBoard = board
            }
            inputView = hopBoard
        } else {
            inputView = nil
        }
        reloadInputViews()
    }

    // SwiftTerm exposes inputAccessoryView as a settable var — assign, don't override.
    func installAccessoryBar() {
        inputAccessoryView = makeAccessory()
        applyBoardPreference()
    }

    func setCtrlArmed(_ armed: Bool) {
        ctrlButton?.accessibilityValue = armed ? "armed" : nil
        ctrlButton?.setNeedsUpdateConfiguration()
    }

    /// ⇧ armed — the same sticky-modifier contract as ctrl and alt, and the
    /// same announcement (a tinted background alone is invisible to
    /// VoiceOver and to any test that would catch it breaking).
    func setShiftArmed(_ armed: Bool) {
        shiftButton?.accessibilityValue = armed ? "armed" : nil
        shiftButton?.setNeedsUpdateConfiguration()
    }

    func setCmdArmed(_ armed: Bool) {
        cmdButton?.accessibilityValue = armed ? "armed" : nil
        cmdButton?.setNeedsUpdateConfiguration()
    }

    /// Can this app carry a chord only CSI-u can express (anything with ⌘)?
    /// Same gate, same reasons, as shiftEnterSequence().
    var enhancedKeys: Bool {
        remote.kbdEnhanced || runningAppName.localizedCaseInsensitiveContains("claude")
            || runningAppName.localizedCaseInsensitiveContains("codex")
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
        // A UIView deinits on the main thread in practice; assumeIsolated
        // makes that a CHECKED fact instead of an unspoken one, and gives
        // this nonisolated deinit legal access to the MainActor timers.
        MainActor.assumeIsolated {
            repeatTimer?.invalidate()
            momentumLink?.invalidate()  // a live CADisplayLink outlives the view
        }
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
        hairline.backgroundColor = UIColor.label.withAlphaComponent(0.06)
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
        stack.spacing = 3      // 11 Mac keys have to fit; see the widths below
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
            // A MacBook Pro's own keys, in Mac notation, and NOTHING that
            // isn't one (Jian: "you need to be able to simulate a full mac
            // keyboard … other keys that do not exist in a macbook pro
            // keyboard i also do not need them"). The four modifiers are
            // sticky and combine, so every Mac chord is reachable; ^C stays
            // because it is the one chord worth a single tap ("the ctrl+c
            // shortcut is very convenient though, i want that kept").
            // MEASURED, not guessed: eleven keys × these widths + 10 × 3pt
            // gaps + the stack's 8pt lead = 394pt, inside a 402pt phone
            // (at 4pt gaps → ended at 404 and the layout test caught it).
            // The arrows give up 3pt each to pay for the modifiers; the gaps
            // gave up the rest, because a narrower arrow is a missed arrow.
            ("esc", .esc, 34, "escape", nil),
            ("tab", .tab, 36, "tab", nil),
            ("⌃", .ctrl, 32, "control", nil),
            ("⌥", .alt, 32, "option", nil),
            ("⇧", .shift, 32, "shift", nil),
            ("⌘", .cmd, 32, "command", nil),
            ("^C", .ctrlC, 34, "control C", nil),
            ("←", .left, 31, "left arrow", nil),
            ("↓", .down, 31, "down arrow", nil),
            ("↑", .up, 31, "up arrow", nil),
            ("→", .right, 31, "right arrow", nil),
            // Past the fold: real Mac keys that a MacBook reaches with fn,
            // plus hop's own two (the keyboard swap and dismiss). ⇧⏎ stays
            // as a one-tap convenience; ⇧ + return now does it too.
            ("⌫", .backspace, 36, "backspace", nil),
            ("⇧⏎", .shiftEnter, 42, "shift return", nil),
            ("⇞", .pageUp, 36, "page up", nil),
            ("⇟", .pageDown, 36, "page down", nil),
            ("paste", .paste, 48, "paste", nil),
            ("⌨", .board, 36, "hop keyboard", nil),
            ("⌄", .dismiss, 32, "hide keyboard", nil)
        ]
        for (label, key, width, spoken, hold) in keys {
            var cfg = UIButton.Configuration.filled()
            cfg.title = label
            cfg.baseForegroundColor = .label
            cfg.background.backgroundColor = .hopKey
            cfg.background.cornerRadius = 9
            // The hairline every card in the app now wears; flat fills next
            // to the switcher's lit tiles read as an older generation of UI.
            cfg.background.strokeColor = UIColor.label.withAlphaComponent(0.08)
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
            if key == .shift { shiftButton = btn }
            if key == .cmd { cmdButton = btn }
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
                // Ink follows the paper: label on a cap, and on the armed
                // purple the paper's opposite (black on the light-mode
                // lilac, white on the deep purple light mode uses).
                c.baseForegroundColor = armed ? .hopArmedInk : .label
                b.configuration = c
            }
            stack.addArrangedSubview(btn)
        }
        return bar
    }
}

/// A one-finger pan with a real dead zone. A settling fingertip drifts a
/// few points as its pad flattens, and UIKit's pan claims that drift at
/// ~10pt — on the phone every press-and-hold became a scroll ~30ms after
/// touch-down, the hold failed on "movement", and block selection was
/// unreachable (Jian 2026-09-28: "long press no longer triggers the system
/// selector"; diagnostics: `[scroll=began hold=failed]` on 6/6 presses, green
/// in every simulator run because a synthetic press never moves). Movement
/// inside `slop` is withheld from UIKit; past it, the pan sees the full
/// translation from touch-down and begins at once, so a scroll loses nothing
/// but its first `slop` points of latency.
final class SlopPanGestureRecognizer: UIPanGestureRecognizer {
    var slop: CGFloat = 18
    private var start: CGPoint?
    private var released = false
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil, let t = touches.first { start = t.location(in: view); released = false }
        super.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if !released, let s = start, let t = touches.first {
            let p = t.location(in: view)
            guard hypot(p.x - s.x, p.y - s.y) >= slop else { return }
            released = true
        }
        super.touchesMoved(touches, with: event)
    }
    override func reset() {
        super.reset()
        start = nil
        released = false
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
            if g is UIScreenEdgePanGestureRecognizer { selectMark("edge pan asked to begin"); return true }
            // While a selection is live, the drag belongs to SwiftTerm's
            // selection pan — the recognizer that moves the handles. This
            // hook is the VIEW's, so it is asked about EVERY recognizer on
            // it, and the old blanket refusal vetoed the very gesture it
            // meant to protect: handles appeared, then every drag on them
            // was refused (Jian: "cannot drag selection handle even though
            // long press triggered selection mode"). Only OUR pans yield.
            selectMark("shouldBegin pan ours=\(pan === scrollPan || pan === cursorPan) sel=\(selectionActive)")
            if selectionActive { return pan !== scrollPan && pan !== cursorPan && pan !== switchPan }
            if pan === switchPan {
                // Not in pan mode (there, horizontal drags move the grid —
                // Jian scoped the gesture to "when not in panning mode"),
                // not in the chrome strip (the pill's own swipe lives
                // there), and only when the drag is decisively sideways.
                guard !peerSizedGrid, !inChromeStrip(pan) else { return false }
                let v = pan.velocity(in: self)
                return abs(v.x) > abs(v.y) * 1.5
            }
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
            // Two fingers: always, wherever the terminal is.
            if tap === chromeTapTwoFinger { return true }
            let inStrip = inChromeStrip(tap)
            if tap === chromeTap { return inStrip }
            if tap === clickTap {
                guard !inStrip, momentumLink == nil, !brakeTouch else { return false }
                // Mouse mode always arms it (the SGR click path); otherwise
                // it arms exactly when the finger is ON a link — a plain tap
                // on text stays a focus tap.
                // Begin exactly when the tap can DO something: report a
                // mouse click, walk the cursor there, or open a link. This
                // used to admit only the cursor's own row outside an
                // alt-screen app, which blocked the multiline case from the
                // other side — arrowWalk was fixed and taps still did
                // nothing, because the recognizer never started.
                if remoteTakesMouse || remoteAltScreen { return true }
                if let c = cellAt(tap.location(in: self)),
                   arrowWalk(toRow: c.row, col: c.col) != nil { return true }
                return linkUnderTap(tap.location(in: self)) != nil
            }
            if inStrip { return false }   // reaching for controls ≠ asking to type
        }
        // Everything else — tap, double tap, long press — is swallowed while
        // a coast is running, and stops it. Every scroll view on iOS works
        // this way: the first touch on something moving stops it and does
        // nothing else. Without this, stopping a coast also raises the
        // keyboard, shrinking the screen you were trying to read.
        // brakeTouch covers the case where touchesBegan already stopped the
        // coast before this question was asked (touch delivery is immediate
        // with isScrollEnabled false, so momentumLink is nil by now).
        if brakeTouch { if g === selectHold { KBLog.record("sel: hold refused — brake") }; return false }
        if momentumLink != nil {
            if g === selectHold { KBLog.record("sel: hold refused — coasting") }
            Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                .info("coast braked by touch")
            stopMomentum()
            return false
        }
        // Press-and-hold selects — but not in the chrome strip (reaching for
        // controls), and never while a coast is being braked (below).
        if g === selectHold {
            if inChromeStrip(g) { KBLog.record("sel: hold refused — chrome strip y=\(Int(g.location(in: self).y - bounds.origin.y)) reach=\(Int(chromeReach))"); return false }
        }
        // An APPROVED single tap on the terminal body is the user engaging —
        // "a single touch should trigger autofit". This is the one place
        // every tap passes through regardless of focus state: touchesEnded
        // misses recognized taps (the recognizer cancels view touches,
        // probe-proven) and becomeFirstResponder fires only when unfocused.
        // Brakes, strip taps and mouse clicks returned above; pans never
        // reach this line.
        if let tap = g as? UITapGestureRecognizer, tap.numberOfTapsRequired == 1,
           !inChromeStrip(tap) {
            onUserIntent?()
        }
        let ok = super.gestureRecognizerShouldBegin(g)
        if g === selectHold { KBLog.record("sel: hold shouldBegin → \(ok)") }
        return ok
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

    /// And when the two do overlap, the edge swipe wins outright: OUR
    /// recognizers wait for it to fail. This used to be written backwards
    /// (`shouldBeRequiredToFailBy` — "the edge waits for US"), so a sideways
    /// drag from the edge was taken by the scroll/switch pans and the edge
    /// gesture never fired: the swipe-back test had been failing for weeks,
    /// and the session drawer could not open. The edge recognizer fails at
    /// once for a touch that doesn't start at the edge, so nothing else waits.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        other is UIScreenEdgePanGestureRecognizer
    }
}

extension UIResponder {
    /// Whether the software keyboard is on screen, tracked from the system's
    /// show/hide notifications (installed on first read).
    static var hopKeyboardShown: Bool { KeyboardWatch.shared.shown }
}

private final class KeyboardWatch {
    static let shared = KeyboardWatch()
    var shown = false
    private init() {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { [weak self] _ in self?.shown = true }
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) { [weak self] _ in self?.shown = false }
    }
}
