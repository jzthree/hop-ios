import SwiftUI

// Home screen: the fleet, attention-first — the native sibling of the web
// switcher. Search, user/agent/all scope, create, rename, kill.
struct SessionsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [String] = []
    @State private var filter = ""
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
    @StateObject private var notifier = HopNotifier.shared

    private var visible: [HopSession] {
        filterSessions(model.sessions, scope: scope, query: filter)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let err = model.lastError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    Picker("Scope", selection: $scope) {
                        ForEach(SessionScope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                Section {
                    ForEach(visible) { session in
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
                            Button {
                                renameText = session.name
                                renaming = session
                            } label: { Label("Rename", systemImage: "pencil") }
                            Button(role: .destructive) { killTarget = session } label: {
                                Label("Kill", systemImage: "xmark.circle")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { killTarget = session } label: {
                                Label("Kill", systemImage: "xmark.circle")
                            }
                            Button {
                                renameText = session.name
                                renaming = session
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.hopPurple)
                        }
                    }
                } footer: {
                    if visible.isEmpty {
                        Text(filter.isEmpty
                             ? "No \(scope == .agent ? "agent" : "") sessions. Start one with the + button or `hop` on your machine."
                             : "No sessions match “\(filter)”.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $filter, prompt: "Filter sessions")
            .navigationTitle("hop")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "hare.fill").foregroundStyle(Color.hopPurple)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: Binding(
                            get: { notifier.enabled },
                            set: { on in Task { await notifier.setEnabled(on) } }
                        )) {
                            Label("Bell notifications", systemImage: "bell.badge")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; creating = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: String.self) { internalName in
                if let session = model.sessions.first(where: { $0.internalName == internalName }) {
                    TerminalHostView(session: session)
                }
            }
            .refreshable { await model.refreshSessions() }
            .alert("New session", isPresented: $creating) {
                TextField("name", text: $newName)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    Task { if await model.createSession(name: name) { path = [name] } }
                }
            } message: { Text("Letters, numbers, - and _") }
            .alert("Rename session", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("name", text: $renameText)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let s = renaming { Task { _ = await model.renameSession(s, to: renameText) } }
                    renaming = nil
                }
            }
            .alert("Kill session?", isPresented: Binding(get: { killTarget != nil }, set: { if !$0 { killTarget = nil } })) {
                Button("Cancel", role: .cancel) { killTarget = nil }
                Button("Kill", role: .destructive) {
                    if let s = killTarget { Task { _ = await model.killSession(s) } }
                    killTarget = nil
                }
            } message: {
                Text("\(killTarget?.name ?? "") and its running process end for everyone.")
            }
            .onChange(of: notifier.pendingOpen) { _, want in
                // Tapped a bell notification: jump straight to that session.
                guard let want else { return }
                path = [want]
                notifier.pendingOpen = nil
            }
            .task {
                guard let want = ProcessInfo.processInfo.environment["HOP_DEV_OPEN"] else { return }
                for _ in 0..<20 where path.isEmpty {
                    if let hit = model.sessions.first(where: { $0.name == want || $0.internalName == want }) {
                        path = [hit.internalName]
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await model.refreshSessions(silent: true)
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            .task(id: scenePhase) {
                // Previews cost daemon work per call, so only while the list is
                // on screen, only the top few, on a slower cadence than the list.
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await model.refreshPreviews(for: visible.filter(\.live).map(\.internalName))
                    try? await Task.sleep(for: .seconds(9))
                }
            }
        }
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
                        Image(systemName: "cpu").font(.caption2).foregroundStyle(Color.hopGlow.opacity(0.8))
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
    }
}
