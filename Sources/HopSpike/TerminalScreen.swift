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
    /// Arms the summon tip after the first auto-hide.
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
    /// The pill's live travel during a fleet-switch swipe. The web switcher
    /// has no equivalent of this: the pill follows the finger and names the
    /// session you would land on, so the swipe is never blind.
    @State private var pillDragX: CGFloat = 0
    /// An artifact link (hop view) being shown in-app.
    @State private var artifactURL: URL?
    /// The codex-style side panel: this session's published artifacts in a
    /// half-height sheet the terminal stays alive above.
    @State private var artifactPanel = false
    /// The live size verdict for the menu's self-check row.
    @State private var sizeReport = ""
    /// How many artifacts this session has published — decides whether the
    /// pill carries the tray, and a growth while watching raises a toast.
    @State private var artifactCount = 0
    /// The newest artifact this session has published — the menu's one-click
    /// "view latest" (the manifest is newest-first, so it is items.first).
    @State private var latestArtifact: (name: String, url: URL)?
    /// The inbox's contents: this session's recent artifacts, newest first.
    @State private var recentArtifacts: [(name: String, url: URL)] = []
    /// Expanded shows the chip strip under the pill; collapsed just the tray
    /// count. REMEMBERED (Jian: "it will remember that state") — an inbox
    /// you had open stays open on every session until you close it.
    @AppStorage("artifactInboxExpanded") private var artifactInboxExpanded = true
    /// Bumped by the bell; the .task(id:) re-checks the manifest.
    @State private var artifactCheck = 0
    @State private var pillPeek: HopSession?
    @ObservedObject private var network = NetworkConditions.shared
    @State private var controlAction: ControlAction?
    @State private var toast: String?
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
    /// Renaming happens on the desktop too; without this the title here stays
    /// wrong until the next list refresh.
    @State private var renamedTitle: String?
    /// Height of the key bar while the keyboard is up. SwiftUI's keyboard
    /// avoidance insets for the keyboard but NOT for an inputAccessoryView, so
    /// the terminal's frame ran on underneath the strip and autofit sized rows
    /// for space the user cannot see — the bottom of the session, including
    /// claude's prompt line, sat behind the keys.
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
                       fitWidth: fitWidth, autoScale: peerSize != nil, fitTick: fitTick,
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
                       onOthers: { list in
                           withAnimation(.easeOut(duration: 0.2)) { otherViewers = list }
                       },
                       onCollab: { everyone, mine, other in
                           collabEveryone = everyone; iHoldControl = mine; lockedByOther = other
                       },
                       control: $controlAction,
                       onScroll: { scrolledUp = $0 },
                       onChromeTap: {
                           withAnimation(.easeOut(duration: 0.2)) { chromeShown.toggle() }
                           // The lesson's completion: summoning donates the
                           // event, and the tip never shows again.
                           Task { await ChromeSummonTip.chromeSummoned.donate() }
                       },
                       onBackSwipe: { dismiss() },
                       onOpenLink: { link in openLinkSmart(link) },
                       onBufferHeal: { reconnectToken += 1 },
                       onBell: { artifactCheck += 1 },
                       onSizeReport: { sizeReport = $0 },
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

    var body: some View {
        screen
            .saturation(bannerVisible ? 0.55 : 1)
            .opacity(bannerVisible ? 0.82 : 1)
            .animation(.easeInOut(duration: 0.3), value: bannerVisible)
            .padding(.horizontal, 2)
            // Rows begin just under the status text (probe-caught at 26:
            // row zero ran straight through the clock). ~19pt reclaimed over
            // the old safe-area start, and the band above reads as the
            // terminal's own surface instead of dead space.
            .padding(.top, 40)
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
                let dur = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? -1
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
            .confirmationDialog("Links on screen", isPresented: $showLinks, titleVisibility: .visible) {
                // Newest first, and capped: a build log can put dozens on
                // screen and an endless action sheet is unusable.
                ForEach(links.prefix(8), id: \.self) { link in
                    Button(displayLink(link)) { openLinkSmart(link) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(item: $artifactURL) { url in
                ArtifactSheet(url: url)
            }
            // The side-panel experience on a phone: a half-height detent with
            // the terminal INTERACTIVE above it — read the output, browse the
            // rich results, no mode switch. Pull to full height to read a
            // report properly.
            .sheet(isPresented: $artifactPanel) {
                ArtifactsBrowser(serverURL: model.normalizedServerURL,
                                 urlSession: model.urlSession,
                                 nameFor: { name in
                                     model.sessions.first(where: { $0.internalName == name })?.name ?? name
                                 },
                                 onlySession: session.internalName,
                                 servers: model.sessions.filter(\.isPort)
                                     .map { ($0.name, $0.internalName) })
                    .presentationDetents([.fraction(0.45), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
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
                    .padding(.top, windowTopInset() + 52)
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
                // Rotating the phone is a deliberate physical act on THIS
                // session (Jian: "convert to landscape did not trigger
                // autofit") — claim the new shape like the chip tap does,
                // after the rotation's layout settles.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    controlAction = .claimSize
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
            .navigationBarBackButtonHidden(true)
            .statusBarHidden(landscapePhone)
            .overlay(alignment: .top) {
                // Suppressed once the session is gone (the ended card carries
                // its own way back), in landscape (every point is terminal),
                // and while FIND is open — both claim the top edge, and the
                // pill drew over the find bar (probe-caught: the field took
                // typing while the pill covered it).
                if chromeShown, !landscapePhone, !findOpen, goneReason == nil {
                    VStack(spacing: 5) {
                        chromeBar
                        // The inbox, expanded: recent artifacts as chips,
                        // newest first, horizontally scrollable; the last
                        // chip opens the full panel.
                        if artifactInboxExpanded, !recentArtifacts.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(recentArtifacts, id: \.url) { item in
                                        Button { artifactURL = item.url } label: {
                                            Text(item.name)
                                                .font(.caption2.weight(.semibold))
                                                .lineLimit(1).truncationMode(.middle)
                                                .frame(maxWidth: 130)
                                                .padding(.horizontal, 9).padding(.vertical, 5)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .overlay(Capsule().strokeBorder(
                                                    Color.hopGlow.opacity(0.35), lineWidth: 0.5))
                                                .foregroundStyle(Color.hopGlow)
                                        }
                                    }
                                    if artifactCount > recentArtifacts.count {
                                        Button { artifactPanel = true } label: {
                                            Text("all \(artifactCount)")
                                                .font(.caption2.weight(.bold))
                                                .padding(.horizontal, 9).padding(.vertical, 5)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .foregroundStyle(Color.hopPurple)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else if chromeTipAnchor, !landscapePhone, goneReason == nil {
                    // An invisible anchor where the strip lives, carrying the
                    // one-time "tap here" lesson.
                    Color.clear
                        .frame(height: 1)
                        .popoverTip(ChromeSummonTip(), arrowEdge: .top)
                        .padding(.top, windowTopInset() + 8)
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
            .task(id: "\(session.internalName)-\(artifactCheck)") {
                // On open and on every bell: count this session's artifacts.
                // The bell fires the moment hop view copies the file, and the
                // manifest write follows within milliseconds — the small delay
                // covers that gap. Growth while watching gets a toast, so a
                // publish is noticed even with the pill hidden.
                try? await Task.sleep(for: .milliseconds(artifactCheck == 0 ? 0 : 1200))
                guard let url = URL(string: model.normalizedServerURL)?
                    .appendingPathComponent("assets/view/manifest.json") else { return }
                var req = URLRequest(url: url)
                req.timeoutInterval = 8
                req.cachePolicy = .reloadIgnoringLocalCacheData
                guard let (data, resp) = try? await model.urlSession.data(for: req),
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let raw = obj["items"] as? [[String: Any]] else { return }
                let mine = raw.filter { ($0["session"] as? String) == session.internalName }
                if mine.count > artifactCount, artifactCount > 0 || artifactCheck > 0 {
                    toast = "New artifact — tap the tray"
                }
                if let base = URL(string: model.normalizedServerURL) {
                    recentArtifacts = mine.prefix(6).compactMap { o in
                        guard let path = o["path"] as? String,
                              let name = o["name"] as? String else { return nil }
                        return (name.removingPercentEncoding ?? name,
                                base.appendingPathComponent(String(path.dropFirst())))
                    }
                } else {
                    recentArtifacts = []
                }
                latestArtifact = recentArtifacts.first
                withAnimation(.easeOut(duration: 0.2)) { artifactCount = mine.count }
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
                // First hide = the practice run (Jian: "let the user practice
                // bringing the menu back the first time"). The tip points at
                // the strip and is dismissed by DOING it — the summon donates
                // the event, and the rule never shows it again.
                chromeTipAnchor = true
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
            // The final shape, at Jian's word: TWO views — switcher and
            // terminal — one visible button between them, and no switch
            // menu in the title at all. The earlier duplication was the
            // button AND a menu; the resolution is the button WITHOUT the
            // menu, not the reverse (removing the button stranded him).
            // The chevron is BACK — fourth ruling, made after the system-bar
            // leak was sealed so every state is deliberate: "it should be a
            // button on the left of the menu." A visible way back that never
            // depends on a menu render; Back stays in the menu too.
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Back to sessions")
            // Mid-swipe the title becomes the DESTINATION: past the commit
            // threshold you read the name you will land on, not the one you
            // are leaving. Release inside the threshold and nothing happens.
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
            // The tray: present exactly when there is something in it, one
            // tap to the panel (⋯ → Artifacts was "a bit inconvenient" —
            // Jian — and hidden besides). Appears within a beat of an agent
            // publishing, because hop view rings the bell.
            // The artifact INBOX toggle (Jian: "expandable inbox on the
            // menu… it will remember that state"): the tray shows the count;
            // tapping expands or collapses the chip strip under the pill,
            // and the choice persists across sessions.
            if artifactCount > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        artifactInboxExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: artifactInboxExpanded ? "tray.full.fill" : "tray.full")
                        Text("\(artifactCount)").font(.caption2.weight(.bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.hopGlow)
                    .frame(height: 34)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(artifactInboxExpanded
                                    ? "Collapse artifacts" : "Expand artifacts")
            }
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
        // The pill FOLLOWS the finger (rubber-banded past the threshold) and
        // ticks once when the switch arms — the gesture used to be invisible
        // until it had already fired, which made it both undiscoverable and
        // blind about where it was going.
        .offset(x: pillDragX)
        .gesture(DragGesture(minimumDistance: 25)
            .onChanged { v in
                let dx = v.translation.width
                guard abs(dx) > abs(v.translation.height) * 2 else { return }
                let mag = abs(dx)
                let travel = mag <= 50 ? mag : 50 + (mag - 50) * 0.25
                pillDragX = (dx < 0 ? -1 : 1) * min(travel, 68)
                let target = mag > 50
                    ? neighborSession(model.sessions, of: session.internalName,
                                      step: dx < 0 ? 1 : -1)
                    : nil
                if target?.internalName != pillPeek?.internalName {
                    withAnimation(.easeOut(duration: 0.12)) { pillPeek = target }
                    if target != nil {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
            .onEnded { v in
                withAnimation(.spring(duration: 0.3)) { pillDragX = 0 }
                let landing = pillPeek
                withAnimation(.easeOut(duration: 0.12)) { pillPeek = nil }
                let dx = v.translation.width
                guard abs(dx) > 50, abs(dx) > abs(v.translation.height) * 2,
                      let next = landing ?? neighborSession(model.sessions,
                                                            of: session.internalName,
                                                            step: dx < 0 ? 1 : -1) else { return }
                model.requestedSession = next.internalName
            })
        .padding(.horizontal, 5)
        .padding(.top, windowTopInset() + 1)
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
            Text(renamedTitle ?? session.name)
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
        .contextMenu { sessionVerbs }
    }

    /// The session-identity verbs (the web sheet's), shared verbatim between
    /// the ⋯ menu's Session section and the title's context menu.
    @ViewBuilder private var sessionVerbs: some View {
        Button { renameText = session.name; renameShown = true } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { taglineText = session.tagline; taglineShown = true } label: {
            Label("Edit tagline", systemImage: "text.quote")
        }
        Menu {
            ForEach(model.folders) { f in
                Button {
                    Task { _ = await model.moveSession(session.internalName, toFolder: f.id) }
                } label: {
                    if session.folderId == f.id {
                        Label(f.name, systemImage: "checkmark")
                    } else { Text(f.name) }
                }
            }
            if session.folderId != nil {
                Button {
                    Task { _ = await model.moveSession(session.internalName, toFolder: nil) }
                } label: { Label("Unfiled", systemImage: "tray") }
            }
        } label: { Label("Move to", systemImage: "folder") }
        Button {
            Task { _ = await model.setOrigin(session.internalName,
                                             createdBy: session.createdBy == "agent" ? "user" : "agent") }
        } label: {
            Label(session.createdBy == "agent" ? "Move to You" : "Move to Agents",
                  systemImage: "arrow.left.arrow.right")
        }
        Button {
            Task {
                if await model.setParked(session, parked: true) { dismiss() }
            }
        } label: { Label("Park", systemImage: "moon.zzz") }
        Button(role: .destructive) { killConfirmShown = true } label: {
            Label("Kill", systemImage: "xmark.circle")
        }
    }

    /// The old menu was twelve items in arrival order — copy next to collab
    /// next to theme, one divider doing all the explaining. Regrouped by what
    /// an item acts ON, most-reached first: the screen's content (find, copy,
    /// links), then how it's drawn (fit, size, theme), then who's here, then
    /// the connection.
    private var actionsMenu: some View {
        Menu {
            Section {
                Button { dismiss() } label: {
                    Label("Back to sessions", systemImage: "chevron.left")
                }
            }
            // State-conditional, and FIRST: while the socket is verified
            // live a Reconnect row is dead weight — and it was the one row
            // that pushed the menu past the keyboard-up fold (the pixels
            // caught it clipped even after the submenu consolidation; the
            // AX-coordinate tap had quietly false-passed). During an outage
            // it leads the menu, because then it IS what you came for.
            if status != .live {
                Section {
                    Button { reconnectToken += 1 } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                }
            }
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
                // Artifacts, first-class (Jian: "directly having a place in
                // the menu, one click to view the most recent"). The latest
                // opens straight into the viewer; the panel holds the rest.
                if let latest = latestArtifact {
                    Button {
                        artifactURL = latest.url
                    } label: {
                        Label("View \(latest.name)", systemImage: "sparkles.rectangle.stack")
                    }
                }
                Button { artifactPanel = true } label: {
                    Label(artifactCount > 0 ? "Artifacts (\(artifactCount))" : "Artifacts",
                          systemImage: "tray.full")
                }
                // Fork from INSIDE the session — the moment you want a copy
                // to try something is usually mid-conversation. Switches to
                // the fork; the original keeps running behind you.
                Button {
                    Task {
                        if let fork = await model.forkSession(session.internalName) {
                            model.requestedSession = fork
                        }
                    }
                } label: {
                    Label("Fork session", systemImage: "arrow.triangle.branch")
                }
            }
            // Unnamed on purpose: fit/size/theme explain themselves, and the
            // header row was the difference between the menu fitting the
            // keyboard-up height and scrolling.
            Section {
                // Observer mode: see the peer's whole grid width at once
                // instead of panning — and claim nothing while watching.
                Button { fitWidth.toggle(); fitTick += 1 } label: {
                    Label(fitWidth ? "Actual size" : "Fit to width",
                          systemImage: fitWidth
                            ? "arrow.up.left.and.arrow.down.right"
                            : "arrow.down.right.and.arrow.up.left")
                }
                // A stepper, not two one-shot rows: the menu stays up while
                // you tap and the terminal re-fits live behind it, so finding
                // a size is one visit instead of open-tap-reopen per point.
                // Unlabeled: every row here is paid for out of the keyboard-up
                // height budget (see the submenu comment below).
                ControlGroup {
                    Button { setFont(fontSize - 1) } label: {
                        Label("Smaller text", systemImage: "textformat.size.smaller")
                    }
                    Button { setFont(fontSize + 1) } label: {
                        Label("Bigger text", systemImage: "textformat.size.larger")
                    }
                }
                .menuActionDismissBehavior(.disabled)
                Button {
                    lightTheme.toggle()
                    UserDefaults.standard.set(lightTheme, forKey: "termLight")
                } label: {
                    Label(lightTheme ? "Dark terminal" : "Light terminal",
                          systemImage: lightTheme ? "moon.fill" : "sun.max.fill")
                }
            }
            // Sharing and Session fold into SUBMENUS. Not for tidiness: with
            // the keyboard up the menu's visible height is ~11 rows, and the
            // flat 18-row list scrolled — the probe screenshot showed the
            // Session verbs and Reconnect below a fold nothing hints at, and
            // iOS's AX snapshot truncated the tail outright (the suite lost
            // Reconnect). A menu you must scroll blind is a menu you can't
            // glance; every top-level item is now on screen at once. The
            // session verbs keep a flat fast path: long-press the title.
            Section {
                Menu {
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
                } label: {
                    Label(viewers.count > 1 ? "Sharing — \(viewers.count) here" : "Sharing",
                          systemImage: "person.2")
                }
                // The web sheet's session verbs, reachable WITHOUT leaving
                // the terminal (Jian: "missing rename — review the main hop
                // web version"). Same daemon calls the wall menus make.
                Menu { sessionVerbs } label: {
                    Label("Session", systemImage: "slider.horizontal.3")
                }
            }
            Section {
                // The self-check (Jian: "can hop check the size and whether
                // fit succeeded"): what is drawn, what fits, one verdict. A
                // ✗ names the mismatch and taps into the fix instead of
                // leaving it to be discovered as wrapped text.
                if !sizeReport.isEmpty {
                    if sizeReport.contains("✗") {
                        Button { controlAction = .claimSize } label: {
                            Label(sizeReport, systemImage: "exclamationmark.triangle")
                        }
                    } else {
                        Button {} label: {
                            Label(sizeReport, systemImage: "checkmark.circle")
                        }.disabled(true)
                    }
                }
            }
        } label: {
            // Part of the pill, not a floating button: a hairline seam and a
            // bare glyph — the chevron's visual sibling at the other end
            // (Jian: the menu should feel integrated, not overlapping).
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
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

enum ControlAction { case take, release, lock, unlock, links, claimSize, keyboardSettled, wakeCheck }

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
    /// A peer holds the grid, so we render THEIR shape scaled to fit rather
    /// than drawing it at our font and letting it underfill or overflow.
    var autoScale = false
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
    var onOthers: ([HayClient.Viewer]) -> Void = { _ in }
    var onCollab: (Bool, Bool, Bool) -> Void = { _, _, _ in }
    @Binding var control: ControlAction?
    var onScroll: (Bool) -> Void = { _ in }
    var onChromeTap: () -> Void = {}
    var onBackSwipe: () -> Void = {}
    var onOpenLink: (String) -> Void = { _ in }
    var onBufferHeal: () -> Void = {}
    var onBell: () -> Void = {}
    var onSizeReport: (String) -> Void = { _ in }
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
        c.onOthers = onOthers
        c.onBufferHeal = onBufferHeal
        c.onBell = onBell
        c.onSizeReport = onSizeReport
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
        tv.onChromeTap = onChromeTap
        tv.onOpenLink = onOpenLink
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
                ("0" as NSString).size(withAttributes:
                    [.font: UIFont.monospacedSystemFont(ofSize: pt, weight: .regular)]).width
            }
            // Analytic first guess, then measure-and-correct: glyph advances
            // round to pixel boundaries at small sizes, so pure linear scaling
            // left 84 of 90 columns fitting — measured, off by one wrap.
            size = fitFontSize(base: size, baseCellWidth: advance(size),
                               viewWidth: width, gridCols: cols)
            // BOTH axes (Jian: "it can say match while I cannot scroll to
            // bottom"). Width-only fitting left a tall grid's bottom rows
            // below a viewport that deliberately does not scroll — invisible
            // and unreachable. Cap the font by height too, so the WHOLE
            // grid is on screen; the anchor centres the narrower result.
            let rows = context.coordinator.electedRows > 1
                ? context.coordinator.electedRows : uiView.getTerminal().rows
            if rows > 0, uiView.bounds.height > 1 {
                let baseCellH = UIFont.monospacedSystemFont(
                    ofSize: size, weight: .regular).lineHeight
                if baseCellH * CGFloat(rows) > uiView.bounds.height {
                    size = max(4, size * uiView.bounds.height / (baseCellH * CGFloat(rows)))
                }
            }
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
            // A font change re-lays every cell, and SwiftTerm redraws only the
            // rows it believes changed — which is how a rescale left "one line
            // of text at the bottom messed up" (Jian). Mark the whole buffer
            // dirty so nothing stale can survive the pass.
            uiView.getTerminal().updateFullScreen()
            uiView.setNeedsDisplay(uiView.bounds)
            uiView.applyAnchor()
        }
        uiView.applyTheme(light: lightTheme)
        uiView.naturalFontPt = CGFloat(fontSize)
        uiView.runningAppName = model.sessions
            .first(where: { $0.internalName == room })?.runningApp ?? ""

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
        /// Buffer-heal machinery. SwiftTerm's Buffer.resize REWRAPS the
        /// scrollback on every column change and its rewrap is where the
        /// interleaved-lines corruption comes from — Jian's decisive clue:
        /// the bug is iOS-only, same PTY, same bytes, web clean, so the
        /// damage is local. There is no reflow switch to turn off
        /// (reflowWider/Narrower are unconditional), and once the rewrap has
        /// run the buffer itself is wrong — repainting redraws the damage.
        /// The daemon still holds the truth, so after a column-changing
        /// transition settles we quietly reconnect: the bounded replay
        /// rebuilds the buffer from the daemon's grid. Once per elected
        /// grid, so a heal can never loop.
        private var healTask: Task<Void, Never>?
        private var healedForGrid: (cols: Int, rows: Int)?
        var onBufferHeal: (() -> Void)?
        var onBell: (() -> Void)?
        /// The size self-check (Jian: "can hop check the size and whether
        /// fit succeeded"): a one-line verdict — local grid vs the room's
        /// elected grid vs what this screen fits — emitted on every event
        /// that can change any of the three. ✓ means the three-way story is
        /// consistent; ✗ names the mismatch instead of leaving it to be
        /// discovered as wrapped text.
        var onSizeReport: ((String) -> Void)?

        func emitSizeReport() {
            guard let t = view?.getTerminal() else { return }
            let grid = "\(t.cols)×\(t.rows)"
            let elected = electedCols > 1 ? "\(electedCols)×\(electedRows)" : "—"
            let gridOK = electedCols <= 1 || (t.cols == electedCols && t.rows == electedRows)
            let fit = view?.naturalFit().map { "\($0.cols)×\($0.rows)" } ?? "—"
            let capacity = view?.drawnRows ?? 0
            let cut = capacity > 0 ? max(0, t.rows - capacity) : 0
            let verdict = !gridOK ? "✗ grid ≠ session \(elected)"
                : cut > 0 ? "✗ bottom \(cut) rows off screen"
                : "✓ fit ok"
            onSizeReport?("\(grid) drawn · fits \(fit) · \(verdict)")
        }

        func scheduleBufferHeal(cols: Int, rows: Int) {
            if let done = healedForGrid, done == (cols, rows) { return }
            healedForGrid = (cols, rows)
            healTask?.cancel()
            healTask = Task { @MainActor [weak self] in
                // After the font/pin churn settles — healing mid-transition
                // would snapshot into a grid still changing under it.
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, !Task.isCancelled, self.isLive else { return }
                self.wakeMark("buffer heal: refetching snapshot for \(cols)x\(rows)")
                self.onBufferHeal?()
            }
        }
        /// The last deliberate claim this client sent, so the confirming
        /// active_size is recognised as OURS even though the live fitted dims
        /// still describe the auto-scaled font at that moment.
        private var lastUserClaim: (cols: Int, rows: Int)?
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
            // Not only peer-held: after a rotation the grid WE hold is the
            // wrong shape for the new bounds, and typing must fix that too
            // (Jian: "keyboard typing does not fix it either"). A keystroke
            // asserts the natural fit whenever the room's grid differs from
            // it, whoever nominally holds the size.
            let natural = view?.naturalFit()
            let mismatch = peerHoldsSize
                || (natural.map { electedCols > 1 && ($0.cols != electedCols || $0.rows != electedRows) } ?? false)
            guard isLive, mismatch, !observeOnly, userIsLooking,
                  fittedCols > 1, fittedRows > 1,
                  Date().timeIntervalSince(lastReclaimAt) > 1 else { return }
            lastReclaimAt = Date()
            // A keystroke on THIS terminal is deliberate by definition —
            // carry the flag that wins outright. Claim the NATURAL fit: the
            // live fitted dims describe the auto-scaled font while a peer
            // holds the grid, and claiming those would take the peer's own
            // size — a keystroke that changes nothing.
            let claim = view?.naturalFit() ?? (cols: fittedCols, rows: fittedRows)
            lastUserClaim = claim
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
                reclaimOnUserIntent()
                // Echo BEFORE the wire: the whole point is not waiting for
                // it. The original text goes to the daemon either way; only
                // printables render early, and reconcile eats the server's
                // copy when it returns.
                let echoed = echo.onInput(text, enabled: echoEligible)
                if !echoed.isEmpty { view?.feed(text: echoed) }
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
        private let onRenamed: (String) -> Void
        private let onGone: (String) -> Void
        private let onPresence: ([HayClient.Viewer]) -> Void
        private let onCollab: (Bool, Bool, Bool) -> Void
        private let onScroll: (Bool) -> Void
        /// Presence minus ourselves — set after construction, like
        /// onRetryState, to keep the init signature from growing again.
        var onOthers: ([HayClient.Viewer]) -> Void = { _ in }
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
            // Taps do NOT claim any more (Jian, revising his own rule:
            // "still only keystroke should"). A tap focuses and scrolls; it
            // is not a statement about whose screen this session belongs to.
            view.onUserIntent = { }
            client.onEvent = { [weak self] event in
                guard let self, let tv = self.view else { return }
                switch event {
                case .sendFailed(let text):
                    // The keystroke that discovered the corpse: into the
                    // replay buffer with every right to be replayed — the
                    // user typed it, the socket lied about being alive.
                    self.pending.append(text, at: Date())
                case .connected:
                    self.retryAttempt = 0      // healthy again: reset backoff
                    self.onRetryState(nil, 0)
                    self.echo.reset()
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
                    // The anchor pass the quiet session never got: live
                    // output queues one, but a session whose whole life is
                    // the snapshot (a fresh shell: two lines, then silence)
                    // painted top-stuck and STAYED there — no further output,
                    // no bounds change, no pass (Jian: "I don't see short
                    // sessions start low"). Anchor on the snapshot itself.
                    tv.queueAnchorPass()
                    tv.queueAnchorPass()
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
                    if cols > 1, rows > 1 { tv.pinnedGrid = (cols, rows) }
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
                    let ourClaim = self.lastUserClaim.map { $0 == (cols, rows) } ?? false
                    if (cols == self.fittedCols && rows == self.fittedRows) || ourClaim {
                        self.wakeMark("active_size \(cols)x\(rows) OURS")
                        self.deferredAdopt = nil        // the flash never renders
                        self.peerHoldsSize = false      // our size won; normal rules
                        // Pin to OUR size too — the local grid must equal
                        // the PTY grid ALWAYS, exactly as xterm.js does on
                        // the web. Left unpinned, SwiftTerm's bounds-refit
                        // could drift a column from the elected width, and a
                        // one-column drift wraps every PTY row's last char
                        // onto the next row's start — Jian's screenshot:
                        // "w"+"gallow", "ji"+"legitimate", stale row tails.
                        // The web never shows it because its grid never
                        // drifts. THIS was the text-rendering bug.
                        self.view?.pinnedGrid = (cols, rows)
                        self.emitSizeReport()
                        self.scheduleBufferHeal(cols: cols, rows: rows)
                        self.onSizeState(nil)
                        self.stopReclaimRetry()
                    } else if mine.cols != cols || mine.rows != rows {
                        // The wake-flash fix, half two (PLAN 17, marker-
                        // proven): on a foreground attach our deliberate
                        // claim wins in ~20ms once sent — painting the
                        // foreign size in the meantime IS the flash. Hold
                        // the adopt; the claim's confirm cancels it. A lost
                        // race still adopts, 1.2s late.
                        // The deferral is GONE. It existed to hide a
                        // foreign-size flash during attach, from before
                        // auto-scale made foreign sizes look intentional —
                        // and it had become the corruptor: the serialized
                        // snapshot painted at the OLD width during the
                        // 1.2s hold, then the adopt resized and SwiftTerm
                        // REWRAPPED the entire just-painted transcript.
                        // First controlled reproduction (sim, 2026-08-06):
                        // intra-word interleaving born exactly here. Adopt
                        // immediately; the grid must be right BEFORE the
                        // snapshot lands, and message order guarantees
                        // active_size arrives first.
                        do {
                            self.wakeMark("active_size \(cols)x\(rows) ADOPT-FOREIGN")
                            self.deferredAdopt = nil
                            self.adoptForeign(cols: cols, rows: rows)
                        }
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
                               token: token, using: urlSession)
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
                                    token: self.token_, using: self.urlSession)
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
            case .wakeCheck:
                runWakeCheck()
            case .claimSize:
                // The chip's tap: ask for our fitted size. The election may
                // refuse (someone typed recently) — the refusal rebroadcast
                // re-arms the chip, which is the honest answer.
                if let claim = view?.naturalFit() ?? (fittedCols > 1 && fittedRows > 1
                                                      ? (cols: fittedCols, rows: fittedRows) : nil) {
                    lastUserClaim = claim
                    client.sendResize(cols: claim.cols, rows: claim.rows, user: true)
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
                self.wakeMark("fastPaint grid=\(t.cols)x\(t.rows) fitted=\(self.fittedCols)x\(self.fittedRows)")
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
                    let term = tv.getTerminal()
                    self.client.connect(base: self.wsBase, httpBase: self.httpBase, room: self.room,
                                        cols: term.cols, rows: term.rows,
                                        token: self.token_, using: self.urlSession)
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
            return (t.cols, t.rows)
        }

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
                  !peerHoldsSize, let v = view else { return false }
            // Re-fit to the CURRENT bounds before reading anything: after a
            // wake the cached fit can still describe the pre-lock layout
            // (keyboard up, different safe area), and claiming stale dims is
            // how a deliberate claim wins the election at the WRONG size.
            v.setNeedsLayout()
            v.layoutIfNeeded()
            let t = v.getTerminal()
            let cols = fittedCols, rows = fittedRows
            guard cols > 1, rows > 1 else { return false }
            guard t.cols != cols || t.rows != rows else {
                wakeMark("\(reason) ok \(cols)x\(rows)")
                return false
            }
            guard Date().timeIntervalSince(lastReclaimAt) > 1 else { return false }
            lastReclaimAt = Date()
            wakeMark("\(reason) MISMATCH grid=\(t.cols)x\(t.rows) fit=\(cols)x\(rows) — re-asserting")
            // POLITE. Maintaining our own grid must never outrank a human
            // typing somewhere else.
            client.sendResize(cols: cols, rows: rows)
            // No claim witness here: this is POLITE maintenance of a grid we
            // already hold. The HOP_CLAIM_MARKER is the e2e witness for
            // DELIBERATE claims only, and writing it here made the wake test
            // read keyboard-settle upkeep as a silent wake-claim.
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
            typedText(text)
        }

        /// The one path every typed character takes, from either keyboard:
        /// armed modifiers apply, then deliver (which buffers, reclaims the
        /// size, and marks typing).
        func typedText(_ raw: String) {
            var text = raw
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
        /// True from the second connect on: the wake path. A fresh open
        /// waits 400ms for the keyboard's layout; a reconnect's view is
        /// already laid out, and every ms of that delay was a ms the
        /// foreign grid stayed on screen.
        private var everConnected = false
        /// Set at every connect entry; the adopt-defer window is measured
        /// from here.
        private var connectStartedAt = Date.distantPast
        /// A foreign active_size held back while a deliberate claim races
        /// it. If the claim confirms first, the flash never renders; if
        /// nothing confirms, the late adopt fires — correctness over
        /// cosmetics.
        private var deferredAdopt: (cols: Int, rows: Int)?

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
            scheduleBufferHeal(cols: cols, rows: rows)
            onSizeState("\(cols)×\(rows)")
            startReclaimRetry()
            // Repaint EVERY cell after a reflow. SwiftTerm redraws the rows it
            // knows changed, and a resize invalidates that bookkeeping — which
            // is how a grid change leaves "the last few lines messed up"
            // (Jian). updateFullScreen marks the whole buffer dirty; the
            // display pass then has nothing stale to preserve.
            tv.getTerminal().updateFullScreen()
            tv.setNeedsDisplay(tv.bounds)
            tv.applyAnchor()
            emitSizeReport()
            onGridChange()
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

        func scheduleKeyboardSettleCheck() {
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
            let delayMs = everConnected ? 0 : 400
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
            let cols = fittedCols > 0 ? fittedCols : (t?.cols ?? 0)
            let rows = fittedRows > 0 ? fittedRows : (t?.rows ?? 0)
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
            KBLog.record("fit \(newCols)x\(newRows) bounds=\(Int(source.bounds.width))x\(Int(source.bounds.height))")
            fittedCols = newCols
            fittedRows = newRows
            view?.drawnRows = newRows
            view?.drawnCols = newCols
            view?.queueAnchorPass()
            emitSizeReport()
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
                        t.resize(cols: self.electedCols, rows: self.electedRows)
                    }
                }
            }
            // Before the claim, record only. Sending now would reshape the PTY
            // at a height the keyboard is about to take away. Peer-held and
            // observer mode both suppress the send: one borrows the geometry
            // until typing reclaims it, the other borrows it on purpose.
            guard claimed, !peerHoldsSize, !observeOnly else { return }
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
            // In sessions where the APP owns scrolling — claude's alt screen,
            // anything taking wheel events — the local viewport never moves,
            // so "Live" would offer a jump to a place you never left (Jian:
            // "the live button displays even when clicking has no effect").
            let remoteOwnsScrolling = (hv?.remoteAltScreen ?? false) || (hv?.remoteTakesMouse ?? false)
            let inHistory = hasHistory && position < 0.999 && !remoteOwnsScrolling
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
            // hop view rings the bell when it publishes — the bell is the
            // artifact system's own doorbell, so use it: re-check the
            // manifest and the tray appears within a beat of the publish.
            onBell?()
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    }
}

// ── Accessory key bar ──
enum AccessoryKey: Equatable {
    case esc, tab, shiftTab, ctrl, alt, ctrlC, up, down, left, right
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
        case .board: return nil
        // Not static: CSI 13;2u for an app that understands it, plain enter
        // for a shell that would print it as junk. The tap handler asks the
        // view, which tracks the protocol from output.
        case .shiftEnter: return nil
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
    private weak var chromeTapTwoFinger: UITapGestureRecognizer?
    private weak var clickTap: UITapGestureRecognizer?
    /// Big enough for a thumb, small enough not to steal taps meant for the
    /// first line of output. The grid extends under the status bar now, so
    /// the strip must too — a fixed 46 left the tappable band almost
    /// entirely inside the status area (probe-caught: the summon tap fell
    /// through to the keyboard).
    static var chromeStrip: CGFloat { windowTopInset() + 46 }

    /// A link was tapped directly on the grid.
    var onOpenLink: ((String) -> Void)?

    /// The URL under a tap, or nil. Rows are padded to the grid width and
    /// joined without separators, so wrapped URLs connect and the offset
    /// math is exact — see linkHit. Built per tap; the grid is small.
    /// One scan per touch: the gate (gestureRecognizerShouldBegin) and the
    /// handler both ask, milliseconds apart, and each scan builds the whole
    /// grid as a string — measured as one of the costs behind "a bit
    /// laggier". Same point within half a second returns the cached answer.
    private var linkTapCache: (point: CGPoint, at: TimeInterval, link: String?)?

    func linkUnderTap(_ locInView: CGPoint) -> String? {
        if let c = linkTapCache,
           abs(c.point.x - locInView.x) < 2, abs(c.point.y - locInView.y) < 2,
           CACurrentMediaTime() - c.at < 0.5 {
            return c.link
        }
        let link = linkUnderTapUncached(locInView)
        linkTapCache = (locInView, CACurrentMediaTime(), link)
        return link
    }

    private func linkUnderTapUncached(_ locInView: CGPoint) -> String? {
        let t = getTerminal()
        let x = locInView.x - bounds.origin.x
        let y = locInView.y - bounds.origin.y
        let cellH = drawnCellHeight(viewHeight: bounds.height,
                                    drawnRows: drawnRows, terminalRows: t.rows)
        let cellW = bounds.width / CGFloat(max(1, drawnCols > 0 ? drawnCols : t.cols))
        let row = Int(y / max(1, cellH))
        let col = Int(x / max(1, cellW))
        guard row >= 0, row < t.rows, col >= 0, col < t.cols else { return nil }
        var joined = ""
        joined.reserveCapacity(t.rows * (t.cols + 1))
        for r in 0..<t.rows {
            var line = t.getLine(row: r)?.translateToString(trimRight: true) ?? ""
            if line.count > t.cols { line = String(line.prefix(t.cols)) }
            joined += line.padding(toLength: t.cols, withPad: " ", startingAt: 0)
        }
        return linkHit(atOffset: row * t.cols + col, in: joined)
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
        if g.location(in: self).y - bounds.origin.y < Self.chromeStrip { return true }
        guard let window else { return false }
        let onScreen = convert(bounds, to: window).intersection(window.bounds)
        guard !onScreen.isNull else { return false }
        return g.location(in: window).y - onScreen.minY < Self.chromeStrip
    }

    @objc private func handleClickTap(_ g: UITapGestureRecognizer) {
        // A tap that lands ON a URL means "open it" in any mode — claude's
        // own output is full of PR links, and sending a synthetic mouse
        // click at a URL instead of opening it helps nobody.
        if let link = linkUnderTap(g.location(in: self)), let open = onOpenLink {
            open(link)
            return
        }
        guard remoteTakesMouse else { return }
        let t = getTerminal()
        // Visible-relative, like the chrome strip: location(in:) carries the
        // scrollback offset on this scroll view.
        let loc = g.location(in: self)
        let x = loc.x - bounds.origin.x
        let y = loc.y - bounds.origin.y
        let cellH = drawnCellHeight(viewHeight: bounds.height,
                                    drawnRows: drawnRows, terminalRows: t.rows)
        let cellW = bounds.width / CGFloat(max(1, drawnCols))
        let row = min(t.rows, Int(y / max(1, cellH)) + 1)
        let col = min(t.cols, Int(x / max(1, cellW)) + 1)
        onUserIntent?()
        keyHandler?.scrollInput(clickSequence(col: col, row: row))
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
        if g.state == .began { onBackSwipe?() }
    }

    /// "A single touch should trigger autofit" — the coordinator hangs the
    /// size reclaim here. Wired into touchesEnded, NOT becomeFirstResponder:
    /// SwiftTerm only calls the latter when the terminal isn't focused yet
    /// (probe-proven — an already-focused terminal swallowed the tap), while
    /// a completed touch is every tap. Pans and selections never get here —
    /// their recognizers cancel the view's touches — so READING a foreign
    /// grid by panning it stays free of claims.
    var onUserIntent: (() -> Void)?

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
            let cellW = max(6, bounds.width / CGFloat(max(1, drawnCols > 0 ? drawnCols : term.cols)))
            let cellH = drawnCellHeight(viewHeight: bounds.height,
                                        drawnRows: drawnRows, terminalRows: term.rows)
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
        // Delegate = us, for the simultaneity grant: SwiftTerm installs its
        // own long-press on the same view, and without simultaneous
        // recognition exactly one of the two fires — arbitration picked
        // theirs (probe-proven: the menu never appeared).
        hold.delegate = self
        addGestureRecognizer(hold)
        selectHold = hold

        let click = UITapGestureRecognizer(target: self, action: #selector(handleClickTap))
        click.delegate = self
        addGestureRecognizer(click)
        clickTap = click
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
    /// decides there is nothing to delete → hold-⌫ stops repeating (Jian's
    /// regression report). A terminal ALWAYS conceptually has text before
    /// the cursor, and SwiftTerm's deleteBackward handles empty storage by
    /// sending a raw backspace — so answering true is honest AND restores
    /// the repeat. hasText is public-not-open (the replace() wall again), so
    /// a Swift override is refused; UIKit reads it through the ObjC runtime,
    /// and the runtime can answer. Scoped to THIS subclass only.
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
    func naturalFit() -> (cols: Int, rows: Int)? {
        guard bounds.width > 10, bounds.height > 10 else { return nil }
        let f = UIFont.monospacedSystemFont(ofSize: naturalFontPt, weight: .regular)
        let cw = ("0" as NSString).size(withAttributes: [.font: f]).width
        let ch = f.lineHeight
        guard cw > 1, ch > 1 else { return nil }
        return (max(2, Int(bounds.width / cw)), max(2, Int(bounds.height / ch)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let pin = pinnedGrid {
            let t = getTerminal()
            if t.cols != pin.cols || t.rows != pin.rows {
                t.resize(cols: pin.cols, rows: pin.rows)
                t.updateFullScreen()
                setNeedsDisplay(bounds)
            }
        }
        applyAnchor()
    }

    /// How many rows actually hold content, counted from the bottom up with
    /// an early exit — the common cases (full screen, near-empty screen) both
    /// terminate in a handful of rows.
    private var usedRowsCache: Int = -1
    /// Invalidated by output (queueAnchorPass callers) — layout passes during
    /// a keyboard animation then cost a cached Int instead of a full-grid
    /// string scan per frame.
    func invalidateUsedRows() { usedRowsCache = -1 }
    private func usedRows() -> Int {
        if usedRowsCache >= 0 { return usedRowsCache }
        let t = getTerminal()
        var used = 0
        for r in stride(from: t.rows - 1, through: 0, by: -1) {
            let line = t.getLine(row: r)?.translateToString(trimRight: true) ?? ""
            if !line.isEmpty { used = r + 1; break }
        }
        usedRowsCache = used
        return used
    }

    /// Jian's rule, verbatim: "start the terminal lower unless the content is
    /// more than a full screen." A fresh session's two lines used to sit at
    /// the very top — under the status area and the chrome strip, where he
    /// could not even tap a link. Content now rests just above the keyboard,
    /// like every messaging app, and grows upward until it fills the screen;
    /// from then on the terminal behaves classically. A TRANSFORM, like the
    /// letterbox: the grid never changes, so the size election never hears
    /// about any of this, and gesture coordinates map back through the
    /// translation automatically.
    func applyAnchor() {
        // Scrollback means more than a screen of content: classical layout.
        let t = getTerminal()
        var dy: CGFloat = 0
        if pinnedGrid != nil {
            let rows = t.rows
            let capacity = drawnRows > 0 ? drawnRows : rows
            // FULL slack below a short foreign grid too — centring read as
            // "still not working" (Jian): one rule, content low.
            dy = anchorOffset(viewHeight: bounds.height,
                              gridRows: rows, capacityRows: capacity)
        } else if t.buffer.yDisp == 0, !sawScrollback {
            let used = usedRows()
            if used > 0, used < t.rows, bounds.height > 1 {
                let cellH = drawnCellHeight(viewHeight: bounds.height,
                                            drawnRows: drawnRows, terminalRows: t.rows)
                dy = (CGFloat(t.rows - used) * cellH).rounded(.down)
            }
        }
        let wanted = dy > 1 ? CGAffineTransform(translationX: 0, y: dy) : .identity
        if transform != wanted { transform = wanted }
    }

    /// Coalesced anchor pass: output arrives in bursts, and scanning rows per
    /// chunk would run the scan hundreds of times a second under a compile
    /// log. One pass per frame-ish is indistinguishable and free.
    private var anchorQueued = false
    func queueAnchorPass() {
        invalidateUsedRows()
        guard !anchorQueued else { return }
        anchorQueued = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            self?.anchorQueued = false
            self?.applyAnchor()
        }
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
        if let chip = copyChip, let t = touches.first,
           !chip.frame.contains(t.location(in: self)) {
            hideCopyChip()
        }
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
        super.touchesEnded(touches, with: event)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        brakeTouchAt = -1
        super.touchesCancelled(touches, with: event)
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

    private var selectHoldPoint: CGPoint = .zero
    private var keyboardWasUpAtHold = true

    @objc private func handleSelectHold(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            stopMomentum()
            // If the keyboard is about to RISE (we weren't first responder),
            // the layout will churn for ~0.7s — the menu must outwait it or
            // the tap lands in a moved world (probe-traced: sizeChanged
            // right after present, action never fired).
            keyboardWasUpAtHold = isFirstResponder
            _ = becomeFirstResponder()
            selectHoldPoint = g.location(in: self)
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
        case .ended, .cancelled:
            // Finger up: NOW select the word (the pan it installs can't hurt
            // a finished gesture) and offer Copy.
            select(nil)
            selectMark("hold-ended sel=\(selectionActive)")
            guard selectionActive else { return }
            showCopyChip(at: selectHoldPoint)
            // Re-offer after SwiftTerm's selection pan extends the range.
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

    func selectMark(_ line: String) {
        #if DEBUG
        if let m = ProcessInfo.processInfo.environment["HOP_SELECT_MARKER"] {
            let prev = (try? String(contentsOfFile: m, encoding: .utf8)) ?? ""
            try? (prev + line + "\n").write(toFile: m, atomically: true, encoding: .utf8)
        }
        #endif
    }

    @objc private func selectionPanChanged(_ g: UIPanGestureRecognizer) {
        guard g.state == .ended, selectionActive else { return }
        showCopyChip(at: g.location(in: self))
    }

    /// The Copy offer: a hop chip, not the system edit menu. Six probe
    /// cycles established that UIEditMenuInteraction and SwiftTerm's
    /// UITextInput conformance fight — presentation churned the keyboard and
    /// cleared the selection under the menu. The chip is ours: in-process,
    /// steady, and it CAPTURES the selected text the moment it appears, so
    /// nothing that happens to the live selection afterwards can lose it.
    private var copyChip: UIButton?

    private func showCopyChip(at point: CGPoint) {
        guard let captured = getSelection(), !captured.isEmpty else { return }
        copyChip?.removeFromSuperview()
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Copy"
        cfg.image = UIImage(systemName: "doc.on.doc")
        cfg.imagePadding = 5
        cfg.baseForegroundColor = .white
        cfg.background.backgroundColor = .hopRaised
        cfg.background.cornerRadius = 15
        cfg.background.strokeColor = UIColor(white: 1, alpha: 0.14)
        cfg.background.strokeWidth = 0.5
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFont.systemFont(ofSize: 14, weight: .semibold)
            return out
        }
        let chip = UIButton(configuration: cfg)
        chip.accessibilityLabel = "Copy selection"
        chip.addAction(UIAction { [weak self] _ in
            UIPasteboard.general.string = captured
            self?.selectMark("chip-copied \(captured.count) chars")
            #if DEBUG
            if let marker = ProcessInfo.processInfo.environment["HOP_COPY_MARKER"] {
                try? captured.write(toFile: marker, atomically: true, encoding: .utf8)
            }
            #endif
            self?.hideCopyChip()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }, for: .touchUpInside)
        chip.sizeToFit()
        // FIXED slot, top-trailing under the chrome strip (where the size
        // chip taught the eye to look) — NOT at the finger: the system's
        // text-input menu (Paste/Select/Select All, from SwiftTerm's
        // UITextInput) presents there and occluded a finger-anchored chip
        // (screenshot-proven; canPerformAction is public-not-open, so the
        // system menu cannot be suppressed from a subclass). Hosted on the
        // WINDOW: both the terminal's subtree and the SwiftUI hosting
        // boundary are opaque to accessibility — a superview-hosted chip
        // was invisible to VoiceOver and untappable by tests. The window is
        // above all of it.
        guard let win = window else { return }
        _ = point
        let size = chip.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        chip.frame = CGRect(x: win.bounds.width - size.width - 12,
                            y: Self.chromeStrip + 8,
                            width: size.width, height: size.height)
        win.addSubview(chip)
        copyChip = chip
        selectMark("chip-shown")
        // Nudge assistive tech at the new element; the SwiftUI hosting
        // boundary otherwise leaves the chip undiscovered (recorded caveat).
        UIAccessibility.post(notification: .layoutChanged, argument: chip)
        // A selection you walked away from shouldn't leave UI behind.
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self, weak chip] in
            if let chip, chip === self?.copyChip { self?.hideCopyChip() }
        }
    }

    private func hideCopyChip() {
        copyChip?.removeFromSuperview()
        copyChip = nil
    }

    /// The hop keyboard. Sticky across sessions and launches: a keyboard
    /// choice is a preference, not a per-terminal mood.
    private var hopBoard: HopBoardView?
    static var hopBoardPreferred: Bool {
        get { UserDefaults.standard.bool(forKey: "hopBoard") }
        set { UserDefaults.standard.set(newValue, forKey: "hopBoard") }
    }

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
            // Newline WITHOUT submitting — claude's shift+enter, which no iOS
            // keyboard can produce. Encoded (CSI 13;2u) for apps that speak
            // the protocol or for claude, plain enter otherwise.
            ("⇧⏎", .shiftEnter, 44, "shift return", nil),
            ("⇞", .pageUp, 38, "page up", nil),
            ("⇟", .pageDown, 38, "page down", nil),
            ("paste", .paste, 50, "paste", nil),
            ("⌨", .board, 38, "hop keyboard", nil),
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
            // Two fingers: always, wherever the terminal is.
            if tap === chromeTapTwoFinger { return true }
            let inStrip = inChromeStrip(tap)
            if tap === chromeTap { return inStrip }
            if tap === clickTap {
                guard !inStrip, momentumLink == nil, !brakeTouch else { return false }
                // Mouse mode always arms it (the SGR click path); otherwise
                // it arms exactly when the finger is ON a link — a plain tap
                // on text stays a focus tap.
                return remoteTakesMouse || linkUnderTap(tap.location(in: self)) != nil
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
        if brakeTouch { return false }
        if momentumLink != nil {
            Logger(subsystem: "io.zhoulab.hop.spike", category: "terminal")
                .info("coast braked by touch")
            stopMomentum()
            return false
        }
        // Press-and-hold selects — but not in the chrome strip (reaching for
        // controls), and never while a coast is being braked (below).
        if g === selectHold {
            if inChromeStrip(g) { return false }
        }
        // An APPROVED single tap on the terminal body is the user engaging —
        // "a single touch should trigger autofit". This is the one place
        // every tap passes through regardless of focus state: touchesEnded
        // misses recognized taps (the recognizer cancels view touches,
        // probe-proven) and becomeFirstResponder fires only when unfocused.
        // Brakes, strip taps and mouse clicks returned above; pans never
        // reach this line.
        if let tap = g as? UITapGestureRecognizer, tap.numberOfTapsRequired == 1 {
            onUserIntent?()
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
