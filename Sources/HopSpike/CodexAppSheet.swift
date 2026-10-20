import SwiftUI

/// A thread from the Codex desktop app on the Mac hop runs on.
struct CodexAppThread: Identifiable, Equatable {
    let id: String
    let title: String
    let cwd: String?
    let updatedAt: Double       // ms
    let pinned: Bool
    /// Who writes the thread now: "app", "terminal", "daemon", or nil (free).
    let holder: String?
    let hopSession: String?     // internalName of the hop session running it
    let hopSessionName: String?

    init?(json o: [String: Any]) {
        guard let id = o["id"] as? String else { return nil }
        self.id = id
        title = (o["title"] as? String) ?? "Untitled"
        cwd = o["cwd"] as? String
        updatedAt = (o["updatedAt"] as? NSNumber)?.doubleValue ?? 0
        pinned = (o["pinned"] as? Bool) ?? false
        holder = o["holder"] as? String
        let hop = o["hopSession"] as? [String: Any]
        hopSession = hop?["internalName"] as? String
        hopSessionName = hop?["displayName"] as? String
    }
}

// The Codex app's threads, continued on the phone (Jian: "better integration
// of codex gui … continuing a session in hop and vice versa"). One writer per
// thread is Codex's rule, so a thread the app has open continues here as a
// fork — a copy, the app's own thread untouched — and a free one resumes.
struct CodexAppSheet: View {
    /// Called with the hop session to open once the sheet is gone.
    let onOpen: (String) -> Void
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var threads: [CodexAppThread]?
    @State private var failed = false
    @State private var busy: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if let threads {
                    if threads.isEmpty {
                        Text("No Codex app threads on this Mac.").foregroundStyle(.secondary)
                    }
                    ForEach(threads) { t in
                        Button { Task { await open(t) } } label: { row(t) }
                            .buttonStyle(.plain)
                            .disabled(busy != nil)
                            .accessibilityIdentifier("codex thread \(t.title)")
                    }
                } else if failed {
                    Text("Couldn't read the Codex app's threads.").foregroundStyle(.secondary)
                } else {
                    HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Codex app")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    @ViewBuilder private func row(_ t: CodexAppThread) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t.title).font(.body).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 6) {
                    if let cwd = t.cwd { Text((cwd as NSString).lastPathComponent).lineLimit(1) }
                    Text(Self.ago(t.updatedAt))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if busy == t.id {
                ProgressView().controlSize(.small)
            } else {
                Text(verb(t)).font(.caption.weight(.semibold)).foregroundStyle(Color.hopGlow)
            }
        }
        .contentShape(Rectangle())
    }

    private func verb(_ t: CodexAppThread) -> String {
        if t.hopSession != nil { return "Open in hop" }
        return t.holder == nil ? "Continue" : "Fork here"
    }

    private func load() async {
        if let got = await model.fetchCodexAppThreads() {
            threads = got
            failed = false
        } else if threads == nil {
            failed = true
        }
    }

    private func open(_ t: CodexAppThread) async {
        busy = t.id
        error = nil
        defer { busy = nil }
        guard let name = await model.continueCodexThread(t.id) else {
            error = model.actionError ?? "Couldn't continue that thread"
            return
        }
        dismiss()
        onOpen(name)
    }

    static func ago(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let s = max(0, Date().timeIntervalSince1970 - ms / 1000)
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        return "\(Int(s / 86400))d"
    }
}
