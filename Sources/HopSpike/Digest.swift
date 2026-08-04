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
    let digest: HopDigest
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
                    onOpen(item.session)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.glyph)
                            .font(.caption2)
                            .foregroundStyle(item.tint)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nameFor(item.session))
                                .font(.caption2.weight(.bold).monospaced())
                                .foregroundStyle(item.tint)
                                .textCase(.uppercase)
                            Text(item.headline)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
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
