import SwiftUI

// The home screen: the fleet at a glance, attention-first — the native sibling
// of the web switcher. Pull to refresh; auto-refresh every 5s while visible.
struct SessionsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    // Dev/simulator: auto-open a session so the terminal screen can be driven
    // and screenshotted without touch input.
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(model.sessions.filter { !$0.isPort }) { session in
                        NavigationLink(value: session.internalName) {
                            SessionRow(session: session)
                        }
                    }
                } footer: {
                    if model.sessions.isEmpty {
                        Text("No live sessions. Start one with `hop` on your machine.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("hop")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Image(systemName: "hare.fill").foregroundStyle(Color.hopPurple)
                }
            }
            .navigationDestination(for: String.self) { internalName in
                if let session = model.sessions.first(where: { $0.internalName == internalName }) {
                    TerminalHostView(session: session)
                }
            }
            .refreshable { await model.refreshSessions() }
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
        }
    }
}

struct SessionRow: View {
    let session: HopSession

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(session.live ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 9, height: 9)
                if session.attention {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: 15, height: 15)
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
                            .background(Color.hopPurple.opacity(0.15), in: Capsule())
                            .foregroundStyle(Color.hopPurple)
                    }
                    if session.attention {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                if !session.shortCwd.isEmpty {
                    Text(session.shortCwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
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
