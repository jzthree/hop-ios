import SwiftUI

// Check-backs on the phone (Jian: "the iOS app does not support hop
// checkback"): what hop will type into this session later, what it already
// typed, cancel — and schedule one without typing CLI flags on a phone.
// Same daemon API the web's ⏰ panel and `hop checkback` use.
struct CheckbacksSheet: View {
    let session: HopSession
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var items: [Checkback]?
    @State private var failed = false
    @State private var busy: String?

    // Composer
    enum When: String, CaseIterable, Identifiable {
        case in30 = "In 30 min", in1h = "In 1 hour", in2h = "In 2 hours", in4h = "In 4 hours"
        case at = "At a time…", idle = "When the agent is next idle"
        var id: String { rawValue }
    }
    @State private var message = ""
    @State private var when: When = .in1h
    @State private var at = Date().addingTimeInterval(3600)
    @State private var scheduling = false
    @State private var error: String?
    @FocusState private var messageFocused: Bool

    private var mine: [Checkback] { (items ?? []).filter { $0.session == session.internalName } }
    private var pending: [Checkback] { mine.filter { $0.status == "pending" }.sorted { $0.sortKey < $1.sortKey } }
    private var past: [Checkback] { Array(mine.filter { $0.status != "pending" }.sorted { $0.doneAt > $1.doneAt }.prefix(8)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("What should hop type into \(session.name)?", text: $message, axis: .vertical)
                        .lineLimit(2...5)
                        .focused($messageFocused)
                        .accessibilityIdentifier("checkback message")
                    Picker("When", selection: $when) {
                        ForEach(When.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if when == .at {
                        DatePicker("Time", selection: $at, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                    Button {
                        Task { await schedule() }
                    } label: {
                        HStack {
                            if scheduling { ProgressView().controlSize(.small) }
                            Text("Schedule check-back").fontWeight(.semibold)
                        }
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scheduling)
                    .accessibilityIdentifier("schedule checkback")
                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("New check-back")
                } footer: {
                    Text("hop types the message and presses Enter when the time comes — waiting until the agent is idle, so it never interrupts a turn.")
                }

                Section("Waiting") {
                    if items == nil {
                        ProgressView()
                    } else if failed {
                        Text("Could not load check-backs.").foregroundStyle(.secondary)
                    } else if pending.isEmpty {
                        Text("Nothing waiting on this session.").foregroundStyle(.secondary)
                    }
                    ForEach(pending) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.whenText).font(.caption.weight(.semibold)).foregroundStyle(Color.hopGlow)
                            Text(c.message).font(.subheadline)
                            Text((c.fired ? "fired · waiting for the agent to be idle" : "waiting")
                                 + " · by " + (c.createdBy == "agent" ? "the agent" : "you"))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { Task { await cancel(c) } } label: {
                                Label("Cancel", systemImage: "xmark.circle")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) { Task { await cancel(c) } } label: {
                                Label("Cancel check-back", systemImage: "xmark.circle")
                            }
                        }
                        .opacity(busy == c.id ? 0.4 : 1)
                    }
                }

                if !past.isEmpty {
                    Section("Recent") {
                        ForEach(past) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                Text((c.status == "delivered" ? "typed" : c.status) + " · " + c.whenText)
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(c.message).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("⏰ Check-backs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        if let got = await model.fetchCheckbacks() { items = got; failed = false } else { items = []; failed = true }
    }

    private func schedule() async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let trigger: [String: Any]
        switch when {
        case .in30: trigger = ["in": "30m"]
        case .in1h: trigger = ["in": "1h"]
        case .in2h: trigger = ["in": "2h"]
        case .in4h: trigger = ["in": "4h"]
        case .idle: trigger = ["idle": true]
        case .at:
            let iso = ISO8601DateFormatter()
            trigger = ["at": iso.string(from: at)]
        }
        scheduling = true
        error = nil
        let ok = await model.scheduleCheckback(session: session.internalName, message: text, trigger: trigger)
        scheduling = false
        if ok {
            message = ""
            messageFocused = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } else {
            error = model.actionError ?? "Could not schedule"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func cancel(_ c: Checkback) async {
        busy = c.id
        _ = await model.cancelCheckback(id: c.id)
        busy = nil
        await load()
    }
}
