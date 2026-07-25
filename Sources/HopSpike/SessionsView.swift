import SwiftUI

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
    @State private var killTarget: HopSession?
    @State private var replyTarget: HopSession?
    @State private var replyText = ""
    @AppStorage("groupByProject") private var groupByProject = false
    @State private var showAccount = ProcessInfo.processInfo.environment["HOP_DEV_SHEET"] == "account"
    @State private var contentMatches: [ContentMatch] = []
    /// Asked once, ever. The whole point of this app is being told when an
    /// agent wants you, and that shipped OFF and three taps deep in a menu —
    /// so the one person who'd benefit had to already know it existed.
    @AppStorage("askedAboutNotifications") private var askedAboutNotifications = false
    @State private var offerNotifications = false

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

    /// What the session last said, falling back to what it's for.
    private var replyPrompt: String {
        guard let target = replyTarget else { return "" }
        let lastLine = model.previews[target.internalName]?
            .split(separator: "\n").last.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        if let lastLine, lastLine.count > 2 { return lastLine }
        return target.tagline
    }

    /// Parked sessions are left out on purpose: they don't ring the phone (see
    /// `alertable`), so counting them here would promise a bell that never
    /// comes, for a row that isn't in the list either.
    private var wanting: Int {
        model.sessions.filter { $0.attention && !$0.isPort && !$0.parked }.count
    }

    private var parkedCount: Int { model.sessions.filter { !$0.isPort && $0.parked }.count }

    private var fleetSummary: String {
        let shown = visible.count
        // The denominator is what you could BROWSE to, so parking something
        // doesn't leave the list permanently reading "19 of 24" as though a
        // filter were stuck on. Parked sessions get their own count instead —
        // hidden, but never silently.
        let total = model.sessions.filter { !$0.isPort && !$0.parked }.count
        let scope = shown == total
            ? "\(shown) session\(shown == 1 ? "" : "s")"
            : "\(shown) of \(total)"
        let parkedNote = parkedCount > 0 ? " · \(parkedCount) parked" : ""
        guard wanting > 0 else { return "\(scope) · nothing waiting on you\(parkedNote)" }
        // And say so when the thing waiting isn't one of the rows you can see.
        let hidden = wanting - visible.filter(\.attention).count
        let note = hidden > 0 ? " (\(hidden) not shown here)" : ""
        return "\(scope) · \(wanting) want\(wanting == 1 ? "s" : "") you\(note)\(parkedNote)"
    }

    /// One unlabelled section normally; project buckets when grouping is on.
    /// Filtering always flattens — you're hunting one thing, not browsing.
    private var sections: [(label: String, rows: [HopSession])] {
        guard groupByProject, filter.isEmpty else { return [(label: "", rows: visible)] }
        return groupSessionsByProject(visible)
    }

    // MARK: pieces

    @ViewBuilder
    private func row(for session: HopSession) -> some View {
        NavigationLink(value: session.internalName) {
            SessionRow(session: session, preview: model.previews[session.internalName])
        }
        .contextMenu {
            Button {
                Task { _ = await model.setAgentAccess(session, allowed: !session.agentPermitted) }
            } label: {
                Label(session.agentPermitted ? "Block agent access" : "Allow agent access",
                      systemImage: session.agentPermitted ? "hand.raised.slash" : "cpu")
            }
            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { killTarget = session } label: {
                Label("Kill", systemImage: "xmark.circle")
            }
        }
        // On the ROW, not inside it: listRowBackground only takes effect on the
        // element the List owns. A wash the width of the row is what makes the
        // one that wants you findable while scrolling past nineteen.
        .listRowBackground(session.attention ? Color.hopAttention.opacity(0.13) : nil)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { killTarget = session } label: {
                Label("Kill", systemImage: "xmark.circle")
            }
            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
                .tint(.hopPurple)
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
            if let err = model.lastError, network.isOnline {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                Picker("Scope", selection: $scope) {
                    ForEach(SessionScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            } footer: {
                // With nineteen sessions the header said nothing. The count you
                // actually care about is how many want you — and when that's
                // zero, saying so is the useful answer, not silence.
                Text(fleetSummary)
                    .font(.caption)
                    .foregroundStyle(wanting > 0 ? Color.hopAttention : .secondary)
            }
            ForEach(sections, id: \.label) { section in
                Section {
                    ForEach(section.rows) { row(for: $0) }
                } header: {
                    if !section.label.isEmpty { Text(section.label) }
                }
            }
            if !inScopeMatches.isEmpty || outOfScopeMatches > 0 {
                Section {
                    ForEach(inScopeMatches) { match in
                        NavigationLink(value: match.internalName) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(match.name)
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                Text(match.snippet)
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
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Image(systemName: "hare.fill").foregroundStyle(Color.hopPurple)
                .accessibilityHidden(true)          // decoration, not a control
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: Binding(get: { notifier.enabled },
                                     set: { on in Task { await notifier.setEnabled(on) } })) {
                    Label("Bell notifications", systemImage: "bell.badge")
                }
                Toggle(isOn: $groupByProject) {
                    Label("Group by project", systemImage: "folder")
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
                .toolbar { toolbar }
                .navigationDestination(for: String.self) { name in
                    // Fall back to the last known value: a session that ends
                    // while you're reading it must not blank the screen.
                    if let session = model.sessions.first(where: { $0.internalName == name })
                        ?? model.lastKnown[name] {
                        TerminalHostView(session: session)
                            .task { await model.unpark(session) }
                    } else {
                        ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
                    }
                }
                .refreshable { await model.refreshSessions() }
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
                .alert("Reply to \(replyTarget?.name ?? "")",
                       isPresented: Binding(get: { replyTarget != nil },
                                            set: { if !$0 { replyTarget = nil } })) {
                    TextField("Answer", text: $replyText)
                        .textInputAutocapitalization(.never)
                    Button("Cancel", role: .cancel) { replyTarget = nil }
                    Button("Send") {
                        guard let target = replyTarget else { return }
                        let text = replyText
                        replyTarget = nil
                        Task {
                            let ok = await QuickReply.send(text, to: target.internalName,
                                                           model: model)
                            // Say when it didn't land — a reply that silently
                            // vanished is worse than no reply button. And
                            // confirm when it did: sending into a list with no
                            // visible result is the same uncertainty in the
                            // other direction, so use the haptic iOS reserves
                            // for exactly this.
                            model.lastError = ok ? nil : "Couldn't send to \(target.name)"
                            UINotificationFeedbackGenerator()
                                .notificationOccurred(ok ? .success : .error)
                            if ok { model.markSeen(target) }
                        }
                    }
                    // An empty reply isn't a failed send, it's not a send —
                    // reporting "couldn't send" for it would be a lie.
                    .disabled(replyText.trimmingCharacters(in: .whitespaces).isEmpty)
                } message: {
                    // The question, not the job title. Answering blind is how
                    // you send "y" to something that asked which of three
                    // options you wanted — the preview's last line is already
                    // on screen in the row, and it's what you're replying to.
                    Text(replyPrompt)
                }
                .modifier(SessionDialogs(
                    creating: $creating, newName: $newName,
                    renaming: $renaming, renameText: $renameText,
                    killTarget: $killTarget, path: $path
                ))
                .onChange(of: model.requestedSession) { _, want in
                    guard let want else { return }
                    path = [want]                    // replaces the pushed terminal
                    model.requestedSession = nil
                }
                .onChange(of: notifier.pendingOpen) { _, want in
                    guard let want else { return }   // tapped a bell notification
                    path = [want]
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
                    guard !askedAboutNotifications, !notifier.enabled else { return }
                    for _ in 0..<20 where model.sessions.isEmpty {
                        try? await Task.sleep(for: .milliseconds(400))
                    }
                    guard !model.sessions.isEmpty else { return }
                    askedAboutNotifications = true
                    offerNotifications = true
                }
                .task(id: filter) { await searchContent() }
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

    private func startRename(_ session: HopSession) {
        renameText = session.name
        renaming = session
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
            let names: [String] = sections.flatMap(\.rows)
                .compactMap { $0.live ? $0.internalName : nil }
            await model.refreshPreviews(for: names)
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
            if let hit = model.sessions.first(where: {
                $0.internalName == want || $0.name == want
            }) {
                target = hit.internalName
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
    @Binding var killTarget: HopSession?
    @Binding var path: [String]

    func body(content: Content) -> some View {
        content
            .alert("New session", isPresented: $creating) {
                TextField("name", text: $newName).textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task { if await model.createSession(name: name) { path = [name] } }
                }
            } message: { Text("Letters, numbers, - and _") }
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
                } else {
                    Circle()
                        .fill(session.live ? Color.green : Color.secondary.opacity(0.35))
                        .frame(width: 9, height: 9)
                }
            }
            .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        // At accessibility sizes a name wrapped mid-word
                        // ("Sol-" / "stice"), which reads as a broken row.
                        // Shrink first, truncate second, never hyphenate.
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if !session.runningApp.isEmpty {
                        Text(session.runningApp)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.hopPurple.opacity(0.18), in: Capsule())
                            .foregroundStyle(Color.hopGlow)
                    }
                    if session.createdBy == "agent" {
                        Image(systemName: "cpu").font(.caption2).foregroundStyle(.secondary)
                    } else if session.agentPermitted {
                        Image(systemName: "cpu").font(.caption2)
                            .foregroundStyle(Color.hopGlow.opacity(0.8))
                    }

                }
                if !session.tagline.isEmpty {
                    Text(session.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !session.shortCwd.isEmpty {
                    Text(session.shortCwd)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.head)
                }
                if let preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 9, design: .monospaced))
                        // The preview is a glance aid, not body text. Letting
                        // it scale to accessibility sizes pushed the list down
                        // to two visible sessions, which costs more than the
                        // legibility gains — the name and tagline above still
                        // scale all the way.
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color.hopSurface, in: RoundedRectangle(cornerRadius: 7))
                        .padding(.top, 3)
                }
            }
            Spacer()
            Text(session.relativeTime)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
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
    /// should actually say.
    var spokenSummary: String {
        var parts = [session.name]
        if session.attention { parts.append("wants attention") }
        parts.append(session.live ? "running" : "stopped")
        if !session.runningApp.isEmpty { parts.append(session.runningApp) }
        if !session.tagline.isEmpty { parts.append(session.tagline) }
        parts.append("active \(session.relativeTime) ago")
        return parts.joined(separator: ", ")
    }
}
