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
    @AppStorage("groupByProject") private var groupByProject = false
    @State private var showAccount = ProcessInfo.processInfo.environment["HOP_DEV_SHEET"] == "account"
    @State private var contentMatches: [ContentMatch] = []

    // MARK: data

    private var visible: [HopSession] {
        filterSessions(model.sessions, scope: scope, query: filter)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { killTarget = session } label: {
                Label("Kill", systemImage: "xmark.circle")
            }
            Button { startRename(session) } label: { Label("Rename", systemImage: "pencil") }
                .tint(.hopPurple)
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
            }
            ForEach(sections, id: \.label) { section in
                Section {
                    ForEach(section.rows) { row(for: $0) }
                } header: {
                    if !section.label.isEmpty { Text(section.label) }
                }
            }
            if !contentMatches.isEmpty {
                Section("Found in output") {
                    ForEach(contentMatches) { match in
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
                    } else {
                        ContentUnavailableView("Session not found", systemImage: "questionmark.folder")
                    }
                }
                .refreshable { await model.refreshSessions() }
                .sheet(isPresented: $showAccount) {
                    AccountView().presentationDetents([.medium, .large])
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
                .task(id: scenePhase) { await pollSessions() }
                .task(id: "\(scenePhase)-\(path.isEmpty)") { await pollPreviews() }
                .task { await openDevSessionIfRequested() }
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

    private func openDevSessionIfRequested() async {
        guard let want = ProcessInfo.processInfo.environment["HOP_DEV_OPEN"] else { return }
        for _ in 0..<20 where path.isEmpty {
            if let hit = model.sessions.first(where: { $0.name == want || $0.internalName == want }) {
                path = [hit.internalName]
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
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
            ZStack {
                Circle()
                    .fill(session.live ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 9, height: 9)
                if session.attention {
                    Circle().stroke(Color.red, lineWidth: 2).frame(width: 15, height: 15)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
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
                    if session.attention {
                        Image(systemName: "bell.fill").font(.caption2).foregroundStyle(.red)
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
                        .foregroundStyle(.secondary.opacity(0.85))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 7))
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
