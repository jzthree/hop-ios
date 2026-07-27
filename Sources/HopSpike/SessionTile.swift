import SwiftUI

// One session as a switcher tile: the whole screen at its true grid geometry,
// scaled to the tile — the same shape hop's web switcher renders — with the
// name and state in a slim header. This is the space-efficient half of the
// list/tiles choice: nineteen sessions become a two-column wall of live
// screens instead of a scroll of text rows.
struct SessionTile: View {
    let session: HopSession
    let screen: ScreenPreview?

    var body: some View {
        VStack(spacing: 0) {
            header
            screenBody
        }
        .background(Color.hopSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(session.attention ? Color.hopAttention.opacity(0.8)
                                                : Color.white.opacity(0.07),
                              lineWidth: session.attention ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.attention ? Color.hopAttention
                      : session.live ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(session.name)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if !session.runningApp.isEmpty {
                Text(session.runningApp)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1.5)
                    .background(Color.hopPurple.opacity(0.22), in: Capsule())
                    .foregroundStyle(Color.hopGlow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(session.attention ? Color.hopAttention.opacity(0.13) : Color.hopRaised)
    }

    @ViewBuilder
    private var screenBody: some View {
        GeometryReader { geo in
            if let screen {
                // Type sized so the session's true column count spans the tile:
                // cols * charWidth == tile width. Monospaced advance ≈ 0.6 × the
                // point size, so pt = width / cols / 0.6. A thumbnail, not a
                // reading surface — the tap is the reading surface.
                let pt = max(1.5, geo.size.width / CGFloat(max(20, screen.cols)) / 0.6)
                Text(screen.text)
                    .font(.system(size: pt, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xe6edf3).opacity(0.85))
                    .lineSpacing(0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .padding(4)
                    .clipped()
            } else {
                // No screen yet: the tagline is what the session is FOR, which
                // beats an empty rectangle while the first fetch is in flight.
                Text(session.tagline.isEmpty ? "…" : session.tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            }
        }
        .aspectRatio(0.95, contentMode: .fit)
    }
}
