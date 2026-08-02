import SwiftUI
import TipKit

// Home screen: the fleet, attention-first — the native sibling of the web
// switcher. Search, user/agent/all scope, optional project grouping, and
// create / rename / kill / agent-access.
//
// Structure note: this body is deliberately split into small computed pieces.
// One flat `List { … }` carrying the whole modifier chain blew past SwiftUI's
// type-checker budget ("unable to type-check this expression in reasonable
// time") — a compile-time cliff, not a style preference.
struct SessionsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notifier = HopNotifier.shared
    @StateObject private var network = NetworkConditions.shared

    @State private var path: [String] = []
    @State private var filter = ProcessInfo.processInfo.environment["HOP_DEV_FILTER"] ?? ""
    @State private var scope: SessionScope = {
        switch ProcessInfo.processInfo.environment["HOP_DEV_SCOPE"] {
        case "all": return .all
        case "agent": return .agent
        default: return .user
        }
    }()
    @State private var creating = false
    @State private var newName = ""
    @State private var renaming: HopSession?
    @State private var renameText = ""
    @State private var taglineTarget: HopSession?
    @State private var taglineText = ""
    @State private var killTarget: HopSession?
    @State private var replyTarget: HopSession?
    @State private var newFolderFor: HopSession?
    @State private var newFolderName = ""
    @State private var replyText = ""
    /// Recent (flat) / By project (cwd heuristic) / By folder (Jian's own
    /// filing). Migrates the old Bool preference on first read.
    @AppStorage("groupMode") private var groupModeRaw = ""
    private var groupMode: GroupMode {
        get {
            if let m = GroupMode(rawValue: groupModeRaw) { return m }
            return UserDefaults.standard.bool(forKey: "groupByProject") ? .project : .recent
        }
    }
    private func setGroupMode(_ m: GroupMode) { groupModeRaw = m.rawValue }
    /// The list/tiles choice is the user's: tiles are the web switcher's
    /// space-efficient wall of live screens; the list keeps taglines, swipe
    /// actions and grouping. Neither is objectively right — so a toggle.
    @AppStorage("switcherTiles") private var switcherTiles = false
    /// The list/tiles choice is UserDefaults-STICKY and the suite shares one
    /// app container, so a probe that ends in tiles silently rewrites what
    /// every later wall test is looking at — tiles have no list rows, so row
    /// swipe actions simply do not exist and the failures read as feature
    /// regressions (this cost a long bisect on 2026-07-31). Tests pin the
    /// mode explicitly instead of inheriting whatever ran last.
    private var showTiles: Bool {
        if let v = ProcessInfo.processInfo.environment["HOP_DEV_TILES"] { return v == "1" }
        return switcherTiles
    }
    @State private var showAccount = ProcessInfo.processInfo.environment["HOP_DEV_SHEET"] == "account"
    @State private var contentMatches: [ContentMatch] = []
    /// Rows currently on screen. Previews cost the daemon a render each, so the
    /// budget is small and fixed — this decides WHERE it is spent.
    @State private var visibleRows: Set<String> = []
    @State private var previewSweep = 0
    /// Asked once, ever. The whole point of this app is being told when an
    /// agent wants you, and that shipped OFF and three taps deep in a menu —
    /// so the one person who'd benefit had to already know it existed.
    @AppStorage("askedAboutNotifications") private var askedAboutNotifications = false
    @State private var offerNotifications = false
    /// Same reasoning as the notification offer, same shape: the biometric
    /// lock shipped OFF and three taps deep in Server & account, so the one
    /// person who wanted it reported the app "still does not have biometric
    /// login" — it had had it for weeks. Offer it once, in context.
    @AppStorage("askedAboutBioLock") private var askedAboutBioLock = false
    @State private var offerBioLock = false
    /// Which briefing has been read. Keyed by its timestamp, so dismissing
    /// hides THIS one and the next scheduled digest appears on its own.
    @AppStorage("digestDismissed") private var digestDismissed = ""


    // MARK: data

    private var visible: [HopSession] {
        filterSessions(model.sessions, scope: scope, query: filter)
    }

    /// Attention is counted across the WHOLE fleet, not the filtered view.
    /// Counting only what's on screen meant filtering to one project could
    /// report "nothing waiting on you" while a session in another project was
    /// waiting — the summary quietly agreeing with whatever you'd narrowed to.
    /// Search runs server-side across everything; the scope picker is a local
    /// choice the server never hears about. Reconcile them here.
    private var inScopeMatches: [ContentMatch] {
        let allowed = Set(filterSessions(model.sessions, scope: scope, query: "")
            .map(\.internalName))
        return contentMatches.filter { allowed.contains($0.internalName) }
    }

    private var outOfScopeMatches: Int { contentMatches.count - inScopeMatches.count }

    /// Parked sessions are left out on purpose: they don't ring the phone (see
    /// `alertable`), so counting them here would promise a bell that never
    /// comes, for a row that isn't in the list either.
    private var wanting: Int {
        model.sessions.filter { $0.attention && !$0.isPort && !$0.parked }.count
    }

    private var parkedCount: Int { model.sessions.filter { !$0.isPort && $0.parked }.count }

    /// "Copy screen" from the wall. The marker file exists because the UI
    /// test CANNOT read the pasteboard back: since iOS 16, pasteboard reads
    /// from a backgrounded process (the test runner) are silently denied, so
    /// the probe verifies the action's content through this side channel and
    /// the pasteboard write stays one uninstrumented line.
    private func copyScreen(_ text: String) {
        UIPasteboard.general.string = text
        #if DEBUG
        if let marker = ProcessInfo.processInfo.environment["HOP_COPY_MARKER"] {
            try? text.write(toFile: marker, atomically: true, encoding: .utf8)
        }
        #endif
    }

    /// (shown, total, wanting, hiddenWanting, parked) — one gathering point
    /// for both renderings of the toolbar summary.
    private var fleetCounts: (Int, Int, Int, Int, Int) {
        // The denominator is what you could BROWSE to, so parking something
        // doesn't leave the list permanently reading "19 of 24" as though a
        // filter were stuck on. Parked sessions get their own count instead —
        // hidden, but never silently.
        let total = model.sessions.filter { !$0.isPort && !$0.parked }.count
        return (visible.count, total, wanting,
                wanting - visible.filter(\.attention).count, parkedCount)
    }

    /// The sentence when it fits, the numbers when it doesn't — the slot
    /// between the two toolbar groups used to ellipsize the sentence exactly
    /// at its informative part. VoiceOver always gets the sentence.
    private var summaryText: some View {
        let (shown, total, wanting, hidden, parked) = fleetCounts
        // COMPACT ONLY (Jian, on device: the sentence overlapped the toolbar
        // buttons — ViewThatFits measures the proposal, not the neighbors'
        // appetite). The numbers can't overlap anything; VoiceOver still
        // hears the sentence.
        return Text(fleetSummaryCompact(shown: shown, total: total, wanting: wanting,
                                        hiddenWanting: hidden, parked: parked))
        .lineLimit(1)
        .accessibilityLabel(fleetSummaryLine(shown: shown, total: total,
                                             wanting: wanting,
                                             hiddenWanting: hidden,
                                             parked: parked))
    }

    /// One unlabelled section normally; project buckets when grouping is on.
    /// Filtering always flattens — you're hunting one thing, not browsing.
    private var sections: [(label: String, rows: [HopSession])] {
        guard filter.isEmpty else { return [(label: "", rows: visible)] }
        switch groupMode {
        case .recent: return [(label: "", rows: visible)]
        case .project: return groupSessionsByProject(visible)
        case .folder: return groupSessionsByFolder(visible, folders: model.folders)
        }
    }

    /// "Move to ▸": Jian's folders, Unfiled, New folder…. The daemon owns
    /// the structure; this is the web drag's POST wearing a native menu.
    @ViewBuilder
    private func moveToMenu(_ session: HopSession) -> some View {
        Menu {
            ForEach(model.folders) { f in
                Button {
                    Task { _ = await model.moveSession(session.internalName, toFolder: f.id) }
                } label: {
                    if session.folderId == f.id {
                        Label(f.name, systemImage: "checkmark")
                    } else {
                        Text(f.name)
                    }
                }
            }
            if session.folderId != nil {
                Button {
                    Task { _ = await model.moveSession(session.internalName, toFolder: nil) }
                } label: { Label("Unfiled", systemImage: "tray") }
            }
            Divider()
            Button { newFolderFor = session } label: {
                Label("New folder…", systemImage: "folder.badge.plus")
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }
    }

    // MARK: pieces

    @ViewBuilder
    private func row(for session: HopSession) -> some View {
        NavigationLink(value: session.internalName) {
            SessionRow(session: session, preview: model.previews[session.internalName],
                       screen: model.screens[session.internalName])
        }
        .contextMenu {
            Button {
                Task { _ = await model.setAgentAccess(session, allowed: !session.agentPermitted) }
            } label: {
                Label(session.agentPermitted ? "Block agent access" : "Allow agent access",
                      systemImage: session.agentPermitted ? "hand.raised.slash" : "cpu")
            }
            Button {
                Task { _ = await model.setOrigin(session.internalName,
                                                 createdBy: session.createdBy == "agent" ? "user" : "agent") }
            } label: {
                Label(session.createdBy == "agent" ? "Move to You" : "Move to Agents",
                      systemImage: "arrow.left.arrow.right")
            }
            // The peek lets you READ a screen without opening the session;
            // this is the matching WRITE half — share it without entering
            // the terminal. Menu dismissal is the ack.
            if let grab = copyableScreen(model.screens[session.internalName]?.text) {
                Button { copyScreen(grab) } label: {
                    Label("Copy screen", systemImage: "doc.on.doc")
                }
                // Copy's sibling for OTHER apps: straight to Messages/Mail
                // through the system sheet, no paste step.
                ShareLink(item: grab, subject: Text(session.name)) {
                    Label("Share screen…", systemImage: "square.and.arrow.up")
                }
            }
            // A copy to try something in, while the original runs untouched —
            // claude forks continue the conversation under a fresh id.
            Button {
                Task {
                    if let fork = await model.forkSession(session.internalName) {
                        model.requestedSession = fork
                    }
                }
            } label: {
                Label("Fork session", systemImage: "arrow.triangle.branch")
            }
            moveToMenu(session)
            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
            Button { startTagline(session) } label: { Label("Edit tagline", systemImage: "text.quote") }
            Button {
                Task { _ = await model.setParked(session, parked: true) }
            } label: {
                Label("Park", systemImage: "moon.zzz")
            }
            Button(role: .destructive) { killTarget = session } label: {
                Label("Kill", systemImage: "xmark.circle")
            }
        } preview: {
            // The same long-press peek the tiles have — the two modes differ
            // in layout, not in capability.
            TilePeek(session: session, screen: model.screens[session.internalName])
        }
        // On the ROW, not inside it: listRowBackground only takes effect on the
        // element the List owns. A wash the width of the row is what makes the
        // one that wants you findable while scrolling past nineteen.
        .listRowBackground(session.attention ? Color.hopAttention.opacity(0.13) : nil)
        // Dense rows: the default insets spent ~14pt per row on air.
        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
        .onAppear { visibleRows.insert(session.internalName) }
        .onDisappear { visibleRows.remove(session.internalName) }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { killTarget = session } label: {
                Label("Kill", systemImage: "xmark.circle")
            }
            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
                .tint(.hopPurple)
            // Parking is the web switcher's triage verb the app never had:
            // out of the working set, still running, still searchable.
            // Opening it again (via search) unparks it — that half existed.
            Button {
                Task { _ = await model.setParked(session, parked: true) }
            } label: {
                Label("Park", systemImage: "moon.zzz")
            }
            .tint(.indigo)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Triage without opening anything. Three agents each waiting on a
            // one-word answer used to mean three round trips through a
            // terminal; this is the in-app twin of replying from the lock
            // screen, and shares its send path.
            Button { replyTarget = session; replyText = "" } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
            }
            .tint(.hopAttention)
        }
    }

    /// The handful of sessions worth a preview right now: what's on screen
    /// first, then the rendered order to fill the budget.
    ///
    /// It used to be the first six of the rendered list, full stop. With
    /// nineteen sessions that leaves two-thirds of the fleet showing a name and
    /// no output — and scrolling never changed it, so the rows you were looking
    /// at stayed blank while six off-screen ones stayed fresh. Same cost to the
    /// daemon, pointed where the eyes are.
    private var previewCandidates: [String] {
        let rendered = sections.flatMap(\.rows).filter(\.live).map(\.internalName)
        var onScreen = rendered.filter { visibleRows.contains($0) }
        var off = rendered.filter { !visibleRows.contains($0) }
        // Rotate BOTH segments each poll. The tail sweep alone wasn't
        // enough: LazyVGrid keeps more cells alive than the fetch budget
        // covers, so the "visible" head could exceed the budget by itself —
        // and prefix() then starved the SAME overflow tiles every tick,
        // which is exactly "some sessions just show …" (Jian, on device;
        // also visible in the iteration-161 probe shots, misread then as
        // the sweep not having arrived yet). Round-robin inside each
        // segment keeps visible-first priority while guaranteeing every
        // tile takes a turn.
        if onScreen.count > 1 {
            let shift = previewSweep % onScreen.count
            onScreen = Array(onScreen[shift...]) + Array(onScreen[..<shift])
        }
        if off.count > 1 {
            let shift = previewSweep % off.count
            off = Array(off[shift...]) + Array(off[..<shift])
        }
        // The head must never eat the whole budget: the marker logs showed
        // ~16 "visible" cells consuming every slot, so off-screen names
        // NEVER fetched — the third face of the same starvation bug. Cap
        // the head's share; the tail is guaranteed the rest.
        let headCap = 12
        return Array(onScreen.prefix(headCap)) + off + Array(onScreen.dropFirst(headCap))
    }

    private var listView: some View {
        List {
            // Offline with sessions already loaded looks EXACTLY like a live
            // list — same rows, same relative times quietly going stale. Say
            // so, or the app is lying about how current it is.
            if !network.isOnline {
                Section {
                    Label("Offline — this list may be out of date.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // The verdict on something the user just did. It stays until they
            // dismiss it or try again — a poll succeeding says nothing about a
            // rename the daemon refused.
            if let err = model.actionError {
                Section {
                    Button { model.actionError = nil } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Label(err, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Dismiss")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if let err = model.lastError, network.isOnline {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                // This section held the scope row, then just the summary.
                // Both live in the toolbar now (Jian: "the top part just
                // displays a small text message and still has a lot of blank
                // space") — nothing left here but the wall itself.
                EmptyView()
            }
            // The briefing sits ABOVE the fleet, because it exists to answer
            // "what should I look at" before you start looking. Hidden once
            // dismissed until a newer one is written, and absent entirely
            // until the scheduled job has run at least once.
            if let d = model.digest, d.generatedAt != digestDismissed,
               filter.isEmpty {
                Section {
                    DigestCard(digest: d) { name in
                        path = [resolveSessionName(name, in: model.sessions) ?? name]
                    } onDismiss: {
                        withAnimation(.easeOut(duration: 0.2)) {
                            digestDismissed = d.generatedAt
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 6, trailing: 10))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            if showTiles {
                // The wall honours project grouping the same way the list
                // does — `sections` is one unlabelled bucket when grouping is
                // off, so the ungrouped render is unchanged.
                ForEach(sections, id: \.label) { tileSection in
                Section {
                    // Adaptive, not a fixed pair: two columns on a portrait
                    // phone, four in landscape or on an iPad — the wall uses
                    // whatever width it's given.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 280),
                                                 spacing: 8)],
                              spacing: 8) {
                        ForEach(tileSection.rows) { session in
                            Button { path.append(session.internalName) } label: {
                                SessionTile(session: session,
                                            screen: model.screens[session.internalName])
                            }
                            .buttonStyle(.plain)
                            .tipIf(session.internalName == tileSection.rows.first?.internalName,
                                   PeekTip())
                            .contextMenu {
                                Button {
                                    Task { _ = await model.setAgentAccess(session, allowed: !session.agentPermitted) }
                                } label: {
                                    Label(session.agentPermitted ? "Block agent access" : "Allow agent access",
                                          systemImage: session.agentPermitted ? "hand.raised.slash" : "cpu")
                                }
                                Button {
                                    Task { _ = await model.setOrigin(session.internalName,
                                                                     createdBy: session.createdBy == "agent" ? "user" : "agent") }
                                } label: {
                                    Label(session.createdBy == "agent" ? "Move to You" : "Move to Agents",
                                          systemImage: "arrow.left.arrow.right")
                                }
                                Button { replyTarget = session; replyText = "" } label: {
                                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                                }
                                if let grab = copyableScreen(model.screens[session.internalName]?.text) {
                                    Button { copyScreen(grab) } label: {
                                        Label("Copy screen", systemImage: "doc.on.doc")
                                    }
                                    ShareLink(item: grab, subject: Text(session.name)) {
                                        Label("Share screen…", systemImage: "square.and.arrow.up")
                                    }
                                }
                                Button {
                                    Task {
                                        if let fork = await model.forkSession(session.internalName) {
                                            model.requestedSession = fork
                                        }
                                    }
                                } label: {
                                    Label("Fork session", systemImage: "arrow.triangle.branch")
                                }
                                moveToMenu(session)
                                Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
                                Button { startTagline(session) } label: { Label("Edit tagline", systemImage: "text.quote") }
                                Button {
                                    Task { _ = await model.setParked(session, parked: true) }
                                } label: {
                                    Label("Park", systemImage: "moon.zzz")
                                }
                                Button(role: .destructive) { killTarget = session } label: {
                                    Label("Kill", systemImage: "xmark.circle")
                                }
                            } preview: {
                                // The long-press peek: the whole screen at
                                // reading size — a native "glance without
                                // opening" the web wall has no equivalent of.
                                TilePeek(session: session,
                                         screen: model.screens[session.internalName])
                            }
                            .onAppear { visibleRows.insert(session.internalName) }
                            .onDisappear { visibleRows.remove(session.internalName) }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                } header: {
                    if !tileSection.label.isEmpty { Text(tileSection.label) }
                }
                }
            } else {
            ForEach(sections, id: \.label) { section in
                Section {
                    ForEach(section.rows) { row(for: $0) }
                } header: {
                    if !section.label.isEmpty { Text(section.label) }
                }
            }
            }
            if !inScopeMatches.isEmpty || outOfScopeMatches > 0 {
                Section {
                    ForEach(inScopeMatches) { match in
                        NavigationLink(value: match.internalName) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(match.name)
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                Text(highlightMatches(in: match.snippet, query: filter))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                } header: {
                    Text("Found in output")
                } footer: {
                    // The scope picker filters the list, and the server-side
                    // search doesn't know about it. Silently showing agent
                    // sessions while scoped to You is confusing; silently
                    // HIDING them is worse — you'd conclude the text isn't
                    // anywhere. So filter, and say what was filtered.
                    if outOfScopeMatches > 0 {
                        Text("\(outOfScopeMatches) more in other scopes")
                    }
                }
            }
            if visible.isEmpty && contentMatches.isEmpty {
                Section {
                    EmptyStateView(
                        filtering: !filter.isEmpty,
                        filter: filter,
                        unreachable: model.sessions.isEmpty && model.lastError != nil,
                        offline: !network.isOnline,
                        server: model.normalizedServerURL,
                        scope: scope,
                        retry: { Task { await model.refreshSessions() } },
                        create: { newName = ""; creating = true }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        // Inset-grouped defaults spend ~140pt before the first control and
        // ~20pt on each side — a fifth of the screen and two tile columns'
        // worth of gutter saying nothing. Sessions above the fold, wall to
        // the glass.
        .contentMargins(.top, 0, for: .scrollContent)
        .contentMargins(.horizontal, 6, for: .scrollContent)
        .listSectionSpacing(14)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Image(systemName: "hare.fill").foregroundStyle(Color.hopPurple)
                .accessibilityHidden(true)          // decoration, not a control
        }
        // The summary IS the title: "hop" said nothing while a whole row
        // below said the useful thing over blank space. Tappable when a
        // session wants you — same contract the old footer row carried.
        ToolbarItem(placement: .principal) {
            if wanting > 0 {
                Button { openWanting() } label: {
                    summaryText
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.hopAttention)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the session that wants you")
            } else {
                summaryText
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        // Scope as a dropdown, not a row: You/Agents/All spent a full row of
        // the screen on a choice made once in a while. A Picker inside a Menu
        // gets the system checkmark treatment for free.
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Scope", selection: $scope) {
                    ForEach(SessionScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(scope.rawValue).font(.footnote.weight(.semibold))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.hopGlow)
            }
            .accessibilityLabel("Scope: \(scope.rawValue)")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: Binding(get: { notifier.enabled },
                                     set: { on in Task { await notifier.setEnabled(on) } })) {
                    Label("Bell notifications", systemImage: "bell.badge")
                }
                Picker("Arrange", selection: Binding(get: { groupMode },
                                                     set: { setGroupMode($0) })) {
                    ForEach(GroupMode.allCases, id: \.self) { m in
                        Label(m.label, systemImage: m.icon).tag(m)
                    }
                }
                Toggle(isOn: $switcherTiles) {
                    Label("Tile view", systemImage: "square.grid.2x2")
                }
                // Dismissing a briefing used to be one-way — there was no
                // route back to it, which is a bad trade for a card that
                // holds the one thing you most needed to know. Shown
                // whenever a briefing exists, so it is also how you find one
                // written while the app was closed.
                if model.digest != nil {
                    Button {
                        digestDismissed = ""
                        Task { await model.refreshDigest() }
                    } label: {
                        Label("Show briefing", systemImage: "sparkles")
                    }
                }
                Divider()
                Button { showAccount = true } label: {
                    Label("Server & account", systemImage: "person.crop.circle")
                }
            } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                .accessibilityLabel("New session")
        }
    }

    // MARK: body

    var body: some View {
        NavigationStack(path: $path) {
            listView
                .searchable(text: $filter, prompt: "Filter sessions")
                .navigationTitle("hop")
                // Inline, not large: the large title spent ~50pt of the first
                // screen writing the app's own name. This is a terminal app —
                // Jian's rule is that the real estate belongs to the sessions.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: String.self) { name in
                    // Fall back to the last known value: a session that ends
                    // while you're reading it must not blank the screen.
                    if let session = model.sessions.first(where: { $0.internalName == name })
                        ?? model.lastKnown[name] {
                        TerminalHostView(session: session)
                            .task { await model.unpark(session) }
                            // Handoff: the open session follows you to the
                            // desk. SwiftUI invalidates the activity when
                            // this view goes away, so leaving the session
                            // clears the Mac's Dock icon by itself.
                            .userActivity("io.zhoulab.hop.session.handoff") { activity in
                                activity.isEligibleForHandoff = true
                                activity.isEligibleForSearch = false
                                activity.title = session.name
                                activity.webpageURL = handoffURL(
                                    server: model.normalizedServerURL,
                                    internalName: session.internalName)
                                #if DEBUG
                                if let marker = ProcessInfo.processInfo
                                    .environment["HOP_HANDOFF_MARKER"] {
                                    try? (activity.webpageURL?.absoluteString ?? "nil")
                                        .write(toFile: marker, atomically: true,
                                               encoding: .utf8)
                                }
                                #endif
                            }
                    } else {
                        ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
                    }
                }
                // A physical tick when the scope changes — the dropdown is in
                // the toolbar now, and the haptic closes the loop the moment
                // the wall re-filters. And on every navigation change: opening
                // a session, leaving one, and above all the pill-swipe switch,
                // whose whole feedback would otherwise be a repainted screen.
                .sensoryFeedback(.selection, trigger: scope)
                .sensoryFeedback(.selection, trigger: path)
                .refreshable { await model.refreshSessions() }
                .alert("Lock hop with \(BioLock.biometryName)?", isPresented: $offerBioLock) {
                    Button("Turn on") { BioLock.shared.enabled = true }
                    Button("Not now", role: .cancel) {}
                } message: {
                    Text("These are real terminals on your machine — anyone holding the phone can type into them. hop will ask on launch and whenever it leaves the screen.")
                }
                .alert("Get told when a session wants you?", isPresented: $offerNotifications) {
                    Button("Turn on") { Task { await notifier.setEnabled(true) } }
                    Button("Not now", role: .cancel) {}
                } message: {
                    Text("A bell from an agent raises a notification, a badge, and a haptic — the reason to have this on a phone rather than a tab.")
                }
                .sheet(isPresented: $showAccount) {
                    // .medium clipped the last row once diagnostics arrived;
                    // sized to the content instead of a fixed half-sheet.
                    AccountView().presentationDetents([.fraction(0.75), .large])
                }
                // A sheet, not an alert: answering blind is how you send "y"
                // to something that asked which of three options you wanted.
                // The sheet shows the last meaningful rows in colour — the
                // question itself — above the composer.
                .sheet(item: $replyTarget) { target in
                    ReplySheet(session: target,
                               screen: model.screens[target.internalName],
                               fallback: model.previews[target.internalName] ?? "") { text in
                        Task {
                            let ok = await QuickReply.send(text, to: target.internalName,
                                                           model: model)
                            // Say when it didn't land — a reply that silently
                            // vanished is worse than no reply button. And
                            // confirm when it did: sending into a list with no
                            // visible result is the same uncertainty in the
                            // other direction, so use the haptic iOS reserves
                            // for exactly this.
                            model.actionError = ok ? nil : "Couldn't send to \(target.name)"
                            UINotificationFeedbackGenerator()
                                .notificationOccurred(ok ? .success : .error)
                            if ok { model.markSeen(target) }
                        }
                    }
                }
                .modifier(SessionDialogs(
                    creating: $creating, newName: $newName,
                    renaming: $renaming, renameText: $renameText,
                    taglineTarget: $taglineTarget, taglineText: $taglineText,
                    killTarget: $killTarget, path: $path
                ))
                .alert("New folder",
                       isPresented: Binding(get: { newFolderFor != nil },
                                            set: { if !$0 { newFolderFor = nil } })) {
                    TextField("Folder name", text: $newFolderName)
                        .textInputAutocapitalization(.never)
                    Button("Cancel", role: .cancel) { newFolderFor = nil }
                    Button("Create & move") {
                        let session = newFolderFor
                        let name = newFolderName.trimmingCharacters(in: .whitespaces)
                        newFolderFor = nil
                        newFolderName = ""
                        guard let session, !name.isEmpty else { return }
                        Task {
                            // Create, find the fresh id in the refreshed list,
                            // file the session into it — one gesture's worth.
                            guard await model.createFolder(named: name),
                                  let made = model.folders.first(where: { $0.name == name })
                            else { return }
                            _ = await model.moveSession(session.internalName,
                                                        toFolder: made.id)
                        }
                    }
                }
                // resolveSessionName: outside doors (Handoff, Shortcuts,
                // Spotlight, hop://) can carry a display name or a case
                // variant the daemon would accept (hop2 e4bdd86) but an
                // exact lookup would dead-end at "Session not found". The
                // raw fallback keeps truly-unknown names landing on that
                // screen instead of silently doing nothing.
                .onChange(of: model.requestedSession) { _, want in
                    guard let want else { return }
                    path = [resolveSessionName(want, in: model.sessions) ?? want]
                    model.requestedSession = nil     // replaces the pushed terminal
                }
                .onChange(of: notifier.pendingOpen) { _, want in
                    guard let want else { return }   // tapped a bell notification
                    path = [resolveSessionName(want, in: model.sessions) ?? want]
                    notifier.pendingOpen = nil
                }
                // The route changed, so the request in flight is already lost.
                // The loop below would wait out a whole interval before trying
                // again — up to 30 seconds in Low Data Mode, showing a list
                // from the network you just left, including whether anything
                // is waiting on you.
                .onChange(of: network.pathGeneration) {
                    Task { await model.refreshSessions(silent: true) }
                }
                .task(id: scenePhase) { await pollSessions() }
                .task(id: "\(scenePhase)-\(path.isEmpty)") { await pollPreviews() }
                .task { await openPendingSession() }
                .task {
                    // Once the list is up, not at launch: asking before there's
                    // anything on screen is asking about nothing. Waits for
                    // real sessions so the offer lands in context.
                    let wantNotifications = !askedAboutNotifications && !notifier.enabled
                    let wantBioLock = !askedAboutBioLock && !BioLock.shared.enabled
                        && BioLock.available
                    guard wantNotifications || wantBioLock else { return }
                    for _ in 0..<20 where model.sessions.isEmpty {
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                    guard !model.sessions.isEmpty else { return }
                    // ONE ask per launch — two alerts cannot stack, and the
                    // second would be dismissed unread by the first's tap.
                    if wantNotifications {
                        askedAboutNotifications = true
                        offerNotifications = true
                        return
                    }
                    askedAboutBioLock = true
                    offerBioLock = true
                }
                .task(id: filter) { await searchContent() }
                // Cheap and idempotent: a static file behind the cookie we
                // already send. Re-read on every foreground so a briefing
                // written while the phone slept is there when it wakes.
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await model.refreshDigest()
                }
        }
    }

    // MARK: actions

    /// Content search costs a server-side scan of every session, so it waits
    /// for typing to stop rather than firing per keystroke.
    private func searchContent() async {
        let query = filter
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
            contentMatches = []
            return
        }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        let found = await model.searchContent(query)
        guard !Task.isCancelled else { return }
        contentMatches = found
    }

    /// The bell, answered from the summary line: open the first session that
    /// wants attention, fleet-wide — deliberately ignoring scope and filter,
    /// which are exactly what can be hiding it.
    private func openWanting() {
        let want = model.sessions.first { $0.attention && !$0.isPort && !$0.parked }
        guard let want else { return }
        path = [want.internalName]
    }

    private func startRename(_ session: HopSession) {
        renameText = session.name
        renaming = session
    }

    private func startTagline(_ session: HopSession) {
        taglineText = session.tagline
        taglineTarget = session
    }

    private func pollSessions() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            // Offline: don't wake the radio to fail. NWPathMonitor flips this
            // back the moment there's a path, and the loop resumes.
            if network.isOnline {
                await model.refreshSessions(silent: true)
            }
            // Deliberately NOT slowed while a terminal is open. That was tried
            // on the theory it saved ~3 MB/hour on cellular, but the server
            // gzips: the list is 9.9 KB raw and 1.7 KB on the wire, which
            // URLSession requests by default. Real cost is well under a
            // megabyte an hour, and tripling the interval would have delayed
            // "another agent needs you" — the one thing this poll is for — to
            // buy nothing.
            try? await Task.sleep(for: .seconds(network.isOnline ? network.sessionPollInterval : 4))
        }
    }

    /// Previews cost the daemon a render each: only while the list is
    /// FRONTMOST (a pushed terminal keeps this view alive), only the top few.
    private func pollPreviews() async {
        guard scenePhase == .active, path.isEmpty else { return }
        while !Task.isCancelled {
            // nil = Low Data Mode: skip previews entirely. They're a nicety,
            // and the only part of the list that costs a render per session.
            // Idle rather than return, so switching Low Data Mode back off
            // resumes them instead of waiting for the app to be backgrounded.
            guard let every = network.previewPollInterval else {
                try? await Task.sleep(for: .seconds(20))
                continue
            }
            // Follow the order the list actually RENDERS, not the raw
            // attention order: with grouping on they differ, and fetching the
            // top 6 of the wrong order leaves visible rows preview-less while
            // off-screen ones stay fresh.
            await model.refreshPreviews(for: previewCandidates)
            previewSweep &+= 2
            try? await Task.sleep(for: .seconds(every))
        }
    }

    /// Consume a navigation request that arrived BEFORE this view existed. A
    /// cold-launch quick action sets it during scene connect, and a notification
    /// tapped while the app isn't running sets it as the delegate comes up — in
    /// both cases `onChange` never fires, because the value was already there.
    /// That silently broke the two headline entry points: tap a bell
    /// notification or long-press the icon with the app closed, and nothing
    /// happened at all.
    ///
    /// Waits for the list to know the session, so the destination isn't pushed
    /// against a list that simply hasn't loaded yet.
    private func openPendingSession() async {
        guard let want = model.requestedSession ?? notifier.pendingOpen
                ?? ProcessInfo.processInfo.environment["HOP_DEV_OPEN"] else { return }
        var target: String?
        for _ in 0..<25 {
            // Same folding contract as the warm doors (hop2 e4bdd86).
            if let hit = resolveSessionName(want, in: model.sessions) {
                target = hit
                break
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        model.requestedSession = nil
        notifier.pendingOpen = nil
        if let target { path = [target] }   // gone: drop it, don't push a dead route
    }
}

/// The create/rename/kill prompts, lifted out of the main body so the
/// type-checker only ever sees a handful of modifiers at a time.
private struct SessionDialogs: ViewModifier {
    @EnvironmentObject var model: AppModel
    @Binding var creating: Bool
    @Binding var newName: String
    @Binding var renaming: HopSession?
    @Binding var renameText: String
    @Binding var taglineTarget: HopSession?
    @Binding var taglineText: String
    @Binding var killTarget: HopSession?
    @Binding var path: [String]

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $creating) {
                NewSessionSheet(name: $newName) { name, cwd in
                    Task { if await model.createSession(name: name, cwd: cwd) { path = [name] } }
                }
            }
            .alert("Rename session",
                   isPresented: Binding(get: { renaming != nil },
                                        set: { if !$0 { renaming = nil } })) {
                TextField("name", text: $renameText).textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let s = renaming { Task { _ = await model.renameSession(s, to: renameText) } }
                    renaming = nil
                }
            }
            .alert("Edit tagline",
                   isPresented: Binding(get: { taglineTarget != nil },
                                        set: { if !$0 { taglineTarget = nil } })) {
                TextField("What is this session for?", text: $taglineText)
                Button("Cancel", role: .cancel) { taglineTarget = nil }
                Button("Save") {
                    if let s = taglineTarget {
                        let text = taglineText.trimmingCharacters(in: .whitespaces)
                        Task {
                            let ok = await model.setTagline(s, to: text)
                            model.actionError = ok ? nil : "Couldn't set tagline on \(s.name)"
                        }
                    }
                    taglineTarget = nil
                }
            } message: {
                Text("Shown under the name, in tiles and on the widget — what this session is for. Empty clears it.")
            }
            .alert("Kill session?",
                   isPresented: Binding(get: { killTarget != nil },
                                        set: { if !$0 { killTarget = nil } })) {
                Button("Cancel", role: .cancel) { killTarget = nil }
                Button("Kill", role: .destructive) {
                    if let s = killTarget { Task { _ = await model.killSession(s) } }
                    killTarget = nil
                }
            } message: {
                Text("\(killTarget?.name ?? "") and its running process end for everyone.")
            }
    }
}

/// What to say when the list has nothing in it — and what to do about it.
struct EmptyStateView: View {
    let filtering: Bool
    let filter: String
    let unreachable: Bool
    let offline: Bool
    let server: String
    let scope: SessionScope
    let retry: () -> Void
    let create: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: offline ? "wifi.slash"
                  : unreachable ? "wifi.exclamationmark"
                  : filtering ? "magnifyingglass" : "terminal")
                .font(.system(size: 30))
                .foregroundStyle(unreachable ? .orange : Color.hopPurple)
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if unreachable {
                Button("Try again", action: retry).buttonStyle(.borderedProminent)
            } else if !filtering && scope != .agent {
                Button("New session", action: create).buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var title: String {
        if offline { return "No internet connection" }
        if unreachable { return "Can't reach hop" }
        if filtering { return "No matches" }
        return scope == .agent ? "No agent sessions" : "No sessions yet"
    }

    private var detail: String {
        if offline { return "This phone has no network. hop is probably fine." }
        if unreachable { return "\(server) didn't answer. Check that the daemon and tunnel are up." }
        if filtering { return "Nothing matches “\(filter)”." }
        return scope == .agent
            ? "Sessions started by agents over MCP show up here."
            : "Start one here, or run `hop` on your machine."
    }
}

struct SessionRow: View {
    let session: HopSession
    var preview: String?
    var screen: ScreenPreview?

    var body: some View {
        HStack(spacing: 12) {
            // The dot said two things at once — running/stopped AND wants-you —
            // by ringing a green dot in red, which is easy to miss when you're
            // scanning nineteen rows. Attention now OWNS the dot: amber, filled,
            // with a soft halo. Liveness keeps green, and anything not wanting
            // you stays quiet.
            ZStack {
                if session.attention {
                    Circle().fill(Color.hopAttention.opacity(0.22)).frame(width: 22, height: 22)
                    Circle().fill(Color.hopAttention).frame(width: 11, height: 11)
                        .shadow(color: Color.hopAttention.opacity(0.9), radius: 3.5)
                } else {
                    Circle()
                        .fill(session.live ? Color.hopLive : Color.secondary.opacity(0.35))
                        .shadow(color: session.live ? Color.hopLive.opacity(0.7) : .clear,
                                radius: 2.5)
                        .frame(width: 9, height: 9)
                        .sonar(when: session.busy && session.live, color: .hopLive)
                }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        // At accessibility sizes a name wrapped mid-word
                        // ("Sol-" / "stice"), which reads as a broken row.
                        // Shrink first, truncate second, never hyphenate.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if !session.runningApp.isEmpty {
                        let tint = appTint(session.runningApp)
                        Text(session.runningApp)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(tint.opacity(0.16), in: Capsule())
                            .foregroundStyle(tint)
                    }
                    if session.createdBy == "agent" {
                        Image(systemName: "cpu").font(.caption2).foregroundStyle(.secondary)
                    } else if session.agentPermitted {
                        Image(systemName: "cpu").font(.caption2)
                            .foregroundStyle(Color.hopGlow.opacity(0.8))
                    }
                    // Presence at list distance — same eye the tiles wear.
                    if session.attached {
                        Image(systemName: "eye.fill").font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    // Inline, not a trailing column: the column reserved a
                    // whole gutter for four characters (Jian: the list "is
                    // not using the screen real estate efficiently").
                    Text(session.relativeTime)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if !session.tagline.isEmpty {
                    Text(session.tagline).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else if !session.shortCwd.isEmpty {
                    Text(session.shortCwd)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
                if let preview, !preview.isEmpty {
                    // Coloured when the session has a colour report — the
                    // same ink the tiles use — with the plain text as the
                    // fallback, not a second code path.
                    // FIVE lines, at Jian's word. Two showed the tail of a
                    // command and none of its answer; five is enough to see
                    // what a session is actually doing without opening it,
                    // and the rows still fit several sessions per screen.
                    Text(screen.flatMap { TileInk.snippet($0, lines: 5) }
                         ?? AttributedString(preview))
                        .font(.system(size: 9, design: .monospaced))
                        // The preview is a glance aid, not body text. Letting
                        // it scale to accessibility sizes pushed the list down
                        // to two visible sessions, which costs more than the
                        // legibility gains — the name and tagline above still
                        // scale all the way.
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 5).padding(.vertical, 4)
                        .background(Color.hopSurface, in: RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 2)
        // One row = one utterance. Element-by-element, VoiceOver would read a
        // dot, a name, a badge, a tagline and three lines of raw terminal
        // scrollback — the preview is a glance aid, not something to listen to.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityHint("Opens the terminal")
    }

    /// Internal rather than private so the test can hold it to what a row
    /// should actually say. Shared with the tiles via sessionSpokenSummary —
    /// the two switcher modes must SOUND the same, whatever they look like.
    var spokenSummary: String { sessionSpokenSummary(session) }
}
