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
                              urgency: (o["urgency"] as? String) ?? "fyi")
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
        if shownAt[k] == nil { shownAt[k] = Date() }
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
    /// internalName → display name, for the DATELINE. The agent writes the
    /// story; the app prints whose story it is — "hard to register which is
    /// which" (the maintainer) was the card showing prose with no anchor.
    var nameFor: (String) -> String
    var onOpen: (String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2).foregroundStyle(Color.hopGlow)
                Text("Briefing")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.hopGlow)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Dismiss briefing")
            }
            Text(digest.summary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            // The WHOLE page, always. A briefing that hides its back half
            // behind "5 more" is a feed, not a front page — the fold is the
            // generator's job now (it writes fewer, meatier stories).
            ForEach(digest.items) { item in
                Button {
                    witness?.acted(edition: digest.generatedAt, session: item.session)
                    onOpen(item.session)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Color.clear.frame(width: 0, height: 0)
                            .onAppear { witness?.appeared(edition: digest.generatedAt, session: item.session,
                                                           words: (item.headline + " " + item.why).split(separator: " ").count) }
                            .onDisappear { witness?.disappeared(edition: digest.generatedAt, session: item.session) }
                        Image(systemName: item.glyph)
                            .font(.caption2)
                            .foregroundStyle(item.tint)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                if !readSessions.contains(item.session) {
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
                                .foregroundStyle(readSessions.contains(item.session)
                                                 ? Color.secondary : Color.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if !item.why.isEmpty {
                                Text(item.why)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 2)
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(item.session)")
            }

        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.hopGlow.opacity(0.18), lineWidth: 0.5))
    }
}
