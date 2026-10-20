import SwiftUI

// The briefing the host agent wrote, rendered where you land.
//
// The phone does no thinking here: tools/digest.mjs runs on the host on a
// schedule, writes digest.json into the directory the daemon already serves
// under /assets/, and this fetches it with the session cookie the app already
// holds. No new endpoint, no hop2 change, and nothing to pay for on the phone.

struct DigestItem: Identifiable, Equatable {
    let session: String
    let headline: String
    let why: String
    let urgency: String
    /// The chief-of-staff page: "decide" / "watch" / "done", or "also" for
    /// the headline-only roll-up. Empty on editions written before slots.
    let slot: String
    let recommendation: String
    let replies: [String]
    var id: String { session + headline }

    /// Colour carries the same three-way meaning the wall's dots do, so the
    /// briefing reads as part of the app rather than a foreign document.
    var tint: Color {
        switch urgency {
        case "needs-you": return .hopAttention
        case "blocked": return .orange
        case "finished": return .hopLive
        default: return .secondary
        }
    }

    var glyph: String {
        switch urgency {
        case "needs-you": return "exclamationmark.bubble.fill"
        case "blocked": return "hand.raised.fill"
        case "finished": return "checkmark.circle.fill"
        default: return "info.circle"
        }
    }
}

struct HopDigest: Equatable {
    let generatedAt: String
    let summary: String
    let items: [DigestItem]
    let model: String

    init?(json: [String: Any]) {
        guard let summary = json["summary"] as? String else { return nil }
        self.summary = summary
        generatedAt = (json["generated_at"] as? String) ?? ""
        model = (json["model"] as? String) ?? ""
        items = ((json["items"] as? [[String: Any]]) ?? []).compactMap { o in
            guard let s = o["session"] as? String, let h = o["headline"] as? String
            else { return nil }
            return DigestItem(session: s, headline: h,
                              why: (o["why"] as? String) ?? "",
                              urgency: (o["urgency"] as? String) ?? "fyi",
                              slot: (o["slot"] as? String) ?? "",
                              recommendation: (o["recommendation"] as? String) ?? "",
                              replies: (o["replies"] as? [String]) ?? [])
        }
    }
}

/// The front page: the summary is the headline, every story shows in full
/// under its DATELINE, and every row opens its session. Brevity is the
/// GENERATOR's job — it writes a handful of stories sized to one screen.
/// The briefing's read witness, phone side. A row banks dwell while it is
/// on screen and the app is active; 1.5s earns "glimpsed", the text's
/// reading time (200 wpm) earns "read"; opening the session is "acted".
/// Levels are reported once each, batched, to the daemon's union — so a
/// story read here is not "new" on the desk, and the generator knows what
/// it may tell as a delta next edition.
@MainActor
final class DigestReadWitness: ObservableObject {
    static let glimpseSeconds = 1.5
    private var shownAt: [String: Date] = [:]          // "edition|session" → when it came on screen
    private var banked: [String: TimeInterval] = [:]    // dwell carried across appearances
    private var reported: [String: Int] = [:]           // 0 none, 1 glimpsed, 2 read, 3 acted
    private var pending: [[String: Any]] = []
    private var timer: Timer?
    var active = true                                   // scenePhase == .active
    var send: (([[String: Any]]) async -> Void)?

    private func key(_ edition: String, _ session: String) -> String { "\(edition)|\(session)" }

    func appeared(edition: String, session: String, words: Int) {
        let k = key(edition, session)
        guard shownAt[k] == nil else { return }   // already on screen: no duplicate timers
        shownAt[k] = Date()
        schedule(edition: edition, session: session, words: words)
    }
    func disappeared(edition: String, session: String) {
        let k = key(edition, session)
        if let since = shownAt.removeValue(forKey: k), active { banked[k, default: 0] += Date().timeIntervalSince(since) }
    }
    func acted(edition: String, session: String) {
        report(edition: edition, session: session, level: "acted", rank: 3)
    }
    private func dwell(_ k: String) -> TimeInterval {
        var d = banked[k] ?? 0
        if let since = shownAt[k], active { d += Date().timeIntervalSince(since) }
        return d
    }
    private func schedule(edition: String, session: String, words: Int) {
        let readSeconds = max(Self.glimpseSeconds, Double(words) / 200.0 * 60.0)
        let k = key(edition, session)
        let check = { [weak self] in
            guard let self, self.shownAt[k] != nil, self.active else { return }
            let d = self.dwell(k)
            if d >= readSeconds { self.report(edition: edition, session: session, level: "read", rank: 2) }
            else if d >= Self.glimpseSeconds { self.report(edition: edition, session: session, level: "glimpsed", rank: 1) }
        }
        let banked = dwell(k)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, Self.glimpseSeconds - banked)) { check() }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, readSeconds - banked)) { check() }
    }
    private func report(edition: String, session: String, level: String, rank: Int) {
        let k = key(edition, session)
        guard (reported[k] ?? 0) < rank else { return }
        reported[k] = rank
        pending.append(["edition": edition, "item": session, "level": level, "at": Date().timeIntervalSince1970 * 1000])
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flush() }
        }
    }
    func flush() {
        guard !pending.isEmpty, let send else { return }
        let batch = pending; pending = []
        Task { await send(batch) }
    }
}

struct DigestCard: View {
    let digest: HopDigest
    /// The read witness (owned by the list; nil in previews).
    var witness: DigestReadWitness? = nil
    /// Sessions whose story has been opened FROM this briefing. Unread is
    /// the default state of news: a story you have not tapped carries the
    /// dot, and opening it clears it — the same contract as Mail, so it
    /// needs no explanation.
    var readSessions: Set<String>
    /// Earlier editions, newest first (the current one excluded).
    var earlier: [HopDigest] = []
    /// Types a decision reply into the session (+ Enter); true when delivered.
    var onReply: ((String, String) async -> Bool)? = nil
    /// Read-set for an EARLIER edition (the current one uses readSessions).
    var readSetFor: (String) -> Set<String> = { _ in [] }
    /// internalName → display name, for the DATELINE. The agent writes the
    /// story; the app prints whose story it is — "hard to register which is
    /// which" (the maintainer) was the card showing prose with no anchor.
    var nameFor: (String) -> String
    var onOpen: (String) -> Void
    var onDismiss: () -> Void
    @State private var earlierOpen = false
    @State private var sending: String?
    @State private var sent: Set<String> = []
    @State private var openEditions: Set<String> = []

    /// "3h ago" / "yesterday 4 PM" for an edition stamp.
    static func when(_ stamp: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = iso.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) else { return "" }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        if mins < 60 { return "\(max(1, mins))m ago" }
        if mins < 12 * 60 { return "\(mins / 60)h ago" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "h a" : "EEE h a"
        return f.string(from: d)
    }

    @ViewBuilder private func editionRow(_ ed: HopDigest) -> some View {
        let open = openEditions.contains(ed.generatedAt)
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                if open { openEditions.remove(ed.generatedAt) } else { openEditions.insert(ed.generatedAt) }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text(Self.when(ed.generatedAt))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 62, alignment: .leading)
                Text(ed.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(open ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("briefing edition")
        if open {
            let read = readSetFor(ed.generatedAt)
            ForEach(ed.items) { item in
                storyRow(item, edition: ed.generatedAt, read: read)
            }
            .padding(.leading, 10)
        }
    }

    @ViewBuilder private func storyRow(_ item: DigestItem, edition: String, read: Set<String>? = nil) -> some View {
        let isRead = (read ?? readSessions).contains(item.session)
        VStack(alignment: .leading, spacing: 4) {
        Button {
            witness?.acted(edition: edition, session: item.session)
            onOpen(item.session)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.glyph)
                    .font(.caption2)
                    .foregroundStyle(item.tint)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        if !isRead {
                            Circle().fill(Color.hopGlow)
                                .frame(width: 6, height: 6)
                                .accessibilityLabel("Unread")
                        }
                        Text(nameFor(item.session))
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(item.tint)
                            .textCase(.uppercase)
                    }
                    Text(item.headline)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isRead ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.why.isEmpty {
                        Text(item.why)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // A decision comes with the chief of staff's recommendation
                    // and the replies the reader could give.
                    if !item.recommendation.isEmpty {
                        Text("→ " + item.recommendation)
                            .font(.caption2.italic())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(item.session)")
        // The replies are ANSWERS, not labels: a tap types that reply into
        // the session and presses Enter (Jian: "the decision in briefing is
        // not sent to session when I tap on it" — they were plain text inside
        // the open-the-session button). Own buttons, outside that one, so a
        // chip tap never also opens the session.
        if !item.replies.isEmpty, let onReply {
            HStack(spacing: 6) {
                ForEach(item.replies, id: \.self) { r in
                    let key = edition + "|" + item.session + "|" + r
                    Button {
                        guard sending == nil, !sent.contains(key) else { return }
                        sending = key
                        Task {
                            let ok = await onReply(item.session, r)
                            sending = nil
                            if ok {
                                sent.insert(key)
                                witness?.acted(edition: edition, session: item.session)
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            if sent.contains(key) { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                            else if sending == key { ProgressView().controlSize(.mini) }
                            Text(r)
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(sent.contains(key) ? Color.hopGlow.opacity(0.25) : Color.hopPill, in: Capsule())
                        .foregroundStyle(sent.contains(key) ? Color.hopGlow : Color.primary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(sending != nil || (!sent.isEmpty && sent.contains(where: { $0.hasPrefix(edition + "|" + item.session + "|") })))
                    .accessibilityLabel(sent.contains(key) ? "Sent: \(r)" : "Reply \(r) to \(nameFor(item.session))")
                }
            }
            .padding(.leading, 18)
            .padding(.bottom, 4)
        }
        }
        // The witness counts a STORY as on screen only when the story itself
        // is ≥60% visible — the daemon's contract. The whole card is one List
        // row, so a row-level onAppear marked every story "seen" the moment
        // the card's top edge showed (12 of 12 before; 3 of 12 after, the
        // three actually on screen).
        .onGeometryChange(for: Bool.self) { proxy in
            let f = proxy.frame(in: .global)
            guard f.height > 0 else { return false }
            return f.intersection(UIScreen.main.bounds).height / f.height >= 0.6
        } action: { visible in
            if visible {
                witness?.appeared(edition: edition, session: item.session,
                                  words: (item.headline + " " + item.why).split(separator: " ").count)
            } else {
                witness?.disappeared(edition: edition, session: item.session)
            }
        }
        .onDisappear { witness?.disappeared(edition: edition, session: item.session) }
    }

    /// Stories the reader swiped away, for THIS edition only ("edition|session").
    @AppStorage("digestHiddenStories") private var hiddenRaw = ""
    private func isHidden(_ item: DigestItem) -> Bool {
        hiddenRaw.split(separator: ",").contains(Substring(digest.generatedAt + "|" + item.session))
    }
    private func hide(_ item: DigestItem) {
        // Keep only the current edition's entries: a new edition starts clean.
        var keep = hiddenRaw.split(separator: ",").map(String.init).filter { $0.hasPrefix(digest.generatedAt + "|") }
        keep.append(digest.generatedAt + "|" + item.session)
        withAnimation(.easeOut(duration: 0.2)) { hiddenRaw = keep.joined(separator: ",") }
    }
    private var visibleItems: [DigestItem] { digest.items.filter { !isHidden($0) } }

    /// One List ROW per story (the body is a Group, so inside a Section each
    /// child is its own row): native swipe actions per story — swipe left to
    /// clear it, right to open it (Jian: "I should be able to swipe briefing
    /// one by one"). The Section's inset-grouped background is the card.
    var body: some View {
        Group {
            header
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { onDismiss() } label: { Label("Archive", systemImage: "archivebox") }
                        .tint(Color.hopGlow)
                }
            let slotted = digest.items.contains { !$0.slot.isEmpty }
            if slotted {
                ForEach(["decide", "watch", "done"], id: \.self) { slot in
                    let rows = visibleItems.filter { $0.slot == slot }
                    if !rows.isEmpty {
                        // The slot label rides INSIDE its first story's row:
                        // as a row of its own it was stretched to the list's
                        // minimum row height — the blank bands (Jian: "too
                        // much blank space").
                        ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                            swipeable(item) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if i == 0 { slotLabel(slot) }
                                    storyRow(item, edition: digest.generatedAt)
                                }
                            }
                        }
                    }
                }
                let also = visibleItems.filter { $0.slot == "also" }
                if !also.isEmpty {
                    ForEach(Array(also.enumerated()), id: \.element.id) { i, item in
                        swipeable(item) {
                            VStack(alignment: .leading, spacing: 2) {
                                if i == 0 { slotLabel("also") }
                                alsoRow(item)
                            }
                        }
                    }
                }
            } else {
                ForEach(visibleItems) { item in swipeable(item) { storyRow(item, edition: digest.generatedAt) } }
            }
            if visibleItems.isEmpty && !digest.items.isEmpty {
                Text("All caught up — \(digest.items.count) cleared")
                    .font(.caption).foregroundStyle(.secondary)
                    .modifier(BriefingRow())
            }
            if !earlier.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { earlierOpen.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: earlierOpen ? "chevron.down" : "chevron.right")
                                .font(.caption2.weight(.semibold))
                            Text("Earlier · \(earlier.count)")
                                .font(.caption.weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("earlier briefings")
                    if earlierOpen {
                        ForEach(earlier, id: \.generatedAt) { ed in editionRow(ed) }
                    }
                }
                .padding(.top, 4)
                .modifier(BriefingRow())
            }
        }
    }

    private func slotLabel(_ slot: String) -> some View {
        Text(slot.uppercased())
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(slot == "decide" ? Color.hopAttention : slot == "watch" ? Color.orange
                             : slot == "done" ? Color.hopLive : Color.secondary)
            .padding(.top, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2).foregroundStyle(Color.hopGlow)
                Text("Briefing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.hopGlow)
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss briefing")
            }
            Text(digest.summary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(BriefingRow(top: 11))
    }

    @ViewBuilder private func swipeable<V: View>(_ item: DigestItem, @ViewBuilder _ row: () -> V) -> some View {
        row()
            .modifier(BriefingRow())
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    // Clearing a story is the reader saying "seen it".
                    witness?.acted(edition: digest.generatedAt, session: item.session)
                    hide(item)
                } label: { Label("Clear", systemImage: "checkmark") }
                .tint(Color.hopGlow)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    witness?.acted(edition: digest.generatedAt, session: item.session)
                    onOpen(item.session)
                } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                .tint(Color.hopPurple)
            }
    }

    private func alsoRow(_ item: DigestItem) -> some View {
        Button {
            witness?.acted(edition: digest.generatedAt, session: item.session)
            onOpen(item.session)
        } label: {
            HStack(spacing: 6) {
                Text(nameFor(item.session))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(item.headline)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { witness?.appeared(edition: digest.generatedAt, session: item.session, words: item.headline.split(separator: " ").count) }
        .onDisappear { witness?.disappeared(edition: digest.generatedAt, session: item.session) }
    }
}

/// Every briefing row shares the card's look: raised background, no
/// separators, tight insets — the Section's rounded group is the card.
struct BriefingRow: ViewModifier {
    var top: CGFloat = 4
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: top, leading: 14, bottom: 4, trailing: 12))
            .listRowBackground(Color.hopRaised)
            .listRowSeparator(.hidden)
    }
}
