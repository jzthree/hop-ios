import SwiftUI

// One session as a switcher tile: the session's screen at readable size
// (TileTypography decides what to give up), under a slim header and over a
// one-line tagline. This is the space-efficient half of the list/tiles
// choice — nineteen sessions become a two-column wall of live screens.
//
// The card is built like a lit object, not a filled rect: gradient surface
// (top edge catches the light), hairline stroke that fades downward, soft
// drop shadow for lift, and state expressed as GLOW — the dot blooms in its
// own colour, and a session wanting you wears amber on the ring, the header
// wash, and the shadow itself.
struct SessionTile: View {
    let session: HopSession
    let screen: ScreenPreview?

    // Attention (a question) first; then the agent's phase — working indigo,
    // finished-and-unread cyan, read quiet; then plain liveness.
    private var dotColor: Color {
        if session.attention { return .hopAttention }
        if let tint = phaseTint(session.phase) { return tint }
        return session.live ? .hopLive : .hopDead
    }
    /// The ring's colour when the card has something to say: violet for a
    /// question, indigo for work in flight, cyan for a finished turn nobody
    /// has read. A read session and a plain shell keep the hairline.
    private var ringColor: Color? {
        if session.attention { return .hopAttention }
        switch session.phase {
        case .working: return .hopWorking
        case .doneUnread: return .hopFresh
        default: return nil
        }
    }

    /// The ring: the state colour fading downward, or the plain hairline.
    private var ringGradient: LinearGradient {
        guard let ring = ringColor else { return Color.hopHairline }
        // News wears the spark's edge — a question and an unread turn alike
        // (the question also glows, via the shadow below); work in flight
        // keeps a plain tint, as on the web wall.
        if session.attention || session.phase == .doneUnread { return Color.hopSpark }
        return LinearGradient(colors: [ring.opacity(0.85), ring.opacity(0.4)],
                              startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The title before the content (Jian: "more important for me to
            // see title then content"): the name takes every line it needs,
            // and the terminal miniature below gets whatever is left. The
            // CARD has the fixed shape, so tiles in a row stay one height.
            header
                .layoutPriority(1)
            hairline
            screenBody
            hairline
            footer
                .layoutPriority(1)
        }
        .aspectRatio(0.68, contentMode: .fit)
        .background(Color.hopCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(ringGradient, lineWidth: ringColor == nil ? 1 : 1.5)
                .allowsHitTesting(false)
        )
        // One shadow for the whole card, not one per glyph.
        .compositingGroup()
        .shadow(color: ringColor.map { $0.opacity(0.30) } ?? Color.hopShadow,
                radius: ringColor == nil ? 7 : 10, y: 4)
        // A finished-and-read session steps back a little, so the unread
        // ones are what the eye lands on.
        .opacity(session.phase == .doneRead && !session.attention ? 0.88 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        // One utterance, same words as the list row. Without this VoiceOver
        // walks every rendered terminal line in the thumbnail.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessionSpokenSummary(session))
        .accessibilityHint("Opens the terminal")
    }

    private var hairline: some View {
        Color.hopLine(0.06).frame(height: 0.66)
    }

    private var header: some View {
        // The name owns the header, full width (hop web's card: "the facts
        // move to the card's footer and the name takes the header") — with
        // chips beside it, a long name wrapped in a sliver, mid-word.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor.opacity(0.9), radius: 3)
                // Busy = producing output right now; attention owns its own
                // signal, so the sonar only rings for quiet-but-working. An
                // agent mid-turn rings in its own blue for the whole turn.
                .sonar(when: !session.attention && session.live
                            && (session.phase == .working || (session.phase == nil && session.busy)),
                       color: session.phase == .working ? .hopWorking : .hopLive)
                .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
            // Every line it needs, at Jian's word: the title is what you
            // read a tile for, more than its screen, so a long name wraps
            // and the terminal below gives up the lines.
            Text(session.name)
                .font(.system(size: 12, design: .monospaced).weight(.semibold))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(session.attention ? Color.hopAttention.opacity(0.12)
                    : ringColor.map { $0.opacity(0.10) } ?? .clear)
    }

    @ViewBuilder
    private var screenBody: some View {
        GeometryReader { geo in
            if let screen {
                // Scale-to-fit until the type would stop being readable, then
                // hold the floor and show the LAST rows of the screen instead
                // (TileTypography has the full argument). The right edge clips;
                // line starts carry the information. TileInk styles the same
                // row window the daemon coloured — a real miniature of the
                // terminal, not a grey ghost of it.
                let lines = screen.text.split(separator: "\n",
                                              omittingEmptySubsequences: false).map(String.init)
                let fit = TileTypography.window(lines: lines, cols: screen.cols,
                                                width: geo.size.width - 8,
                                                height: geo.size.height - 8)
                Text(TileInk.attributed(rows: screen.colorRows, lines: lines,
                                        range: fit.range))
                    .font(.system(size: fit.pt, design: .monospaced))
                    .lineSpacing(0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .padding(4)
                    .clipped()
            } else {
                Text("…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            }
        }
        // Fills what the title and footer leave (the card holds the shape).
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: .infinity)
    }

    /// The facts, quiet in the footer: who is on it, the agent glyphs, the
    /// check-backs and the model chip.
    private var facts: some View {
        HStack(spacing: 5) {
            // Someone is ON this session right now — the desk browser, the
            // CLI, another phone. The eye is presence at wall distance.
            if session.attached {
                Image(systemName: "eye.fill").font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
            // Same agent glyphs the rows carry: created-by-agent quiet,
            // agent-permitted in glow.
            if session.createdBy == "agent" {
                Image(systemName: "cpu").font(.system(size: 8)).foregroundStyle(.secondary)
            } else if session.agentPermitted {
                Image(systemName: "cpu").font(.system(size: 8))
                    .foregroundStyle(Color.hopGlow.opacity(0.8))
            }
            if session.checkbacks > 0 {
                Text("⏰\(session.checkbacks)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !session.appChip.isEmpty {
                let tint = appTint(session.agentApp)
                Text(session.appChip)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(tint.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
                    .foregroundStyle(tint)
            }
        }
        .fixedSize()
    }

    /// The tagline is what the session is FOR — the one line Jian reached for
    /// and missed in the first tile build. Always present so tiles in a row
    /// stay the same height; the cwd stands in when a session has no tagline.
    private var footer: some View {
        // TWO lines for the tagline, at Jian's word — the agent writes a
        // sentence, and one caption2 line truncated most of them mid-thought.
        // reservesSpace keeps every tile in a row the same height whether the
        // tagline wraps or is missing; the tile's fixed aspect ratio means the
        // second line is paid for out of the terminal window above, which is
        // the trade he asked for ("it can take a bit of the terminal space").
        // Top-aligned so the clock sits on the first line rather than
        // floating in the middle of a two-line block.
        HStack(alignment: .top, spacing: 6) {
            Text(session.tagline.isEmpty ? session.shortCwd : session.tagline)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                // How stale is this screen — the same clock the rows show.
                Text(session.relativeTime)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                facts
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }
}

/// The long-press peek: the WHOLE screen at reading size, in colour. The tile
/// windows and shrinks; this is the honest document — big enough that the
/// context menu becomes a way to READ a session without opening it.
struct TilePeek: View {
    let session: HopSession
    let screen: ScreenPreview?

    var body: some View {
        if let screen {
            let lines = screen.text.split(separator: "\n",
                                          omittingEmptySubsequences: false).map(String.init)
            let pt: CGFloat = 8
            Text(TileInk.attributed(rows: screen.colorRows, lines: lines,
                                    range: 0..<lines.count))
                .font(.system(size: pt, design: .monospaced))
                .lineSpacing(0)
                // Both axes fixed: the system scales an oversized preview
                // down whole; letting it wrap instead broke every line that
                // mattered (screenshot-caught: "BioLock.swi / ft").
                .fixedSize()
                .padding(10)
                .background(Color.hopSurface)
        } else {
            Text(session.tagline.isEmpty ? session.shortCwd : session.tagline)
                .font(.callout)
                .padding(20)
                .background(Color.hopSurface)
        }
    }
}

/// The "producing output right now" signal: an expanding ring that fades as
/// it grows — sonar, not strobe. One ring per sweep, repeating while the
/// condition holds; the condition is re-evaluated on every list refresh, so
/// a session going quiet stops ringing within a poll.
struct SonarPulse: ViewModifier {
    let active: Bool
    let color: Color
    @State private var expand = false
    /// Reduce Motion means the ring never rings — the dot's glow already
    /// says "live", and an endlessly expanding circle is exactly the motion
    /// the setting asks to be spared.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background {
                if active, !reduceMotion {
                    Circle()
                        .stroke(color.opacity(expand ? 0 : 0.7), lineWidth: 1.5)
                        .scaleEffect(expand ? 3.2 : 1)
                        .onAppear {
                            withAnimation(.easeOut(duration: 1.4)
                                .repeatForever(autoreverses: false)) { expand = true }
                        }
                        .onDisappear { expand = false }
                }
            }
    }
}

extension View {
    func sonar(when active: Bool, color: Color) -> some View {
        modifier(SonarPulse(active: active, color: color))
    }
}

// NOTE: no zoom hero transition here, and that's deliberate. iOS 18's
// .navigationTransition(.zoom) was tried and reverted: its interactive
// dismissal claims the left edge but never actually answered the swipe on a
// bar-less destination — the swipe-back test failed with the terminal wedged
// in-session, with our own edge recognizer removed OR beside it. Swipe-back
// is muscle memory; the hero is delight. Muscle memory wins.
