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
struct DigestCard: View {
    /// Newest first. index 0 is today's paper; leafing back is read-only
    /// history — older editions carry no unread dots and no dismiss.
    let editions: [HopDigest]
    @State private var editionIndex = 0
    private var digest: HopDigest { editions[min(editionIndex, editions.count - 1)] }
    private var isCurrent: Bool { editionIndex == 0 }
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
                Text(isCurrent ? "Briefing" : "Briefing · \(Self.editionStamp(digest))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.hopGlow)
                Spacer()
                if isCurrent {
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
            }
            Text(digest.summary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            // The WHOLE page, always. A briefing that hides its back half
            // behind "5 more" is a feed, not a front page — the fold is the
            // generator's job now (it writes fewer, meatier stories).
            ForEach(digest.items) { item in
                Button {
                    onOpen(item.session)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.glyph)
                            .font(.caption2)
                            .foregroundStyle(item.tint)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                if isCurrent, !readSessions.contains(item.session) {
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
                                .foregroundStyle(isCurrent && readSessions.contains(item.session)
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

            // Leafing back through the stack — a newspaper's back numbers,
            // not a feed. Small on purpose: history is available, today is
            // the point.
            if editions.count > 1 {
                HStack(spacing: 14) {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { editionIndex += 1 }
                    } label: {
                        Label("Older", systemImage: "chevron.left")
                            .font(.caption2.weight(.semibold))
                    }
                    .disabled(editionIndex >= editions.count - 1)
                    Text("\(editionIndex + 1) of \(editions.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { editionIndex -= 1 }
                    } label: {
                        Label("Newer", systemImage: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .labelStyle(.trailingIcon)
                    }
                    .disabled(isCurrent)
                }
                .foregroundStyle(Color.hopPurple)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(Color.hopRaised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.hopGlow.opacity(0.18), lineWidth: 0.5))
    }
}


extension DigestCard {
    /// "Mon 14:40" — enough to place an edition without a date lecture.
    static func editionStamp(_ d: HopDigest) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: d.generatedAt)
            ?? ISO8601DateFormatter().date(from: d.generatedAt)
        guard let date else { return "" }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

/// Label with the icon AFTER the text — SwiftUI has no built-in for it.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}
