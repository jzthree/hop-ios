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

    private var dotColor: Color {
        session.attention ? .hopAttention : session.live ? .hopLive : .hopDead
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            screenBody
            hairline
            footer
        }
        .background(Color.hopCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(session.attention
                              ? LinearGradient(colors: [Color.hopAttention.opacity(0.85),
                                                        Color.hopAttention.opacity(0.4)],
                                               startPoint: .top, endPoint: .bottom)
                              : Color.hopHairline,
                              lineWidth: session.attention ? 1.5 : 1)
                .allowsHitTesting(false)
        )
        // One shadow for the whole card, not one per glyph.
        .compositingGroup()
        .shadow(color: session.attention ? Color.hopAttention.opacity(0.30) : .black.opacity(0.5),
                radius: session.attention ? 10 : 7, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    private var hairline: some View {
        Color.white.opacity(0.06).frame(height: 0.66)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
                .shadow(color: dotColor.opacity(0.9), radius: 3)
            Text(session.name)
                .font(.system(size: 12, design: .monospaced).weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !session.runningApp.isEmpty {
                let tint = appTint(session.runningApp)
                Text(session.runningApp)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background(tint.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(session.attention ? Color.hopAttention.opacity(0.12) : .clear)
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
        .aspectRatio(0.95, contentMode: .fit)
    }

    /// The tagline is what the session is FOR — the one line Jian reached for
    /// and missed in the first tile build. Always present so tiles in a row
    /// stay the same height; the cwd stands in when a session has no tagline.
    private var footer: some View {
        Text(session.tagline.isEmpty ? session.shortCwd : session.tagline)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
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

// NOTE: no zoom hero transition here, and that's deliberate. iOS 18's
// .navigationTransition(.zoom) was tried and reverted: its interactive
// dismissal claims the left edge but never actually answered the swipe on a
// bar-less destination — the swipe-back test failed with the terminal wedged
// in-session, with our own edge recognizer removed OR beside it. Swipe-back
// is muscle memory; the hero is delight. Muscle memory wins.
