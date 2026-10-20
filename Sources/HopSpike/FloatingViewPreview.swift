import SwiftUI
import AVKit

// A new `hop view` delivery, previewed the moment it lands — in a small
// floating card the reader can drag to any corner, flick off the edge, close,
// or tap to open full-size. iOS's picture-in-picture is the model (Jian: "kind
// of similar to minimized video screens on iOS"). The terminal stays usable
// underneath; the card only covers a corner of it.

/// What the card shows: enough to render the preview and open the item.
struct FloatingDelivery: Equatable, Identifiable {
    let item: ArtifactItem
    let url: URL
    var id: String { item.path + "@\(item.mtime)" }

    enum Kind { case image, video, page }
    var kind: Kind {
        let ext = (item.name as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(ext) { return .image }
        if ["mp4", "mov", "m4v", "mp3", "m4a", "wav", "aac"].contains(ext) { return .video }
        return .page
    }

    static func == (a: FloatingDelivery, b: FloatingDelivery) -> Bool { a.id == b.id }
}

/// Which corner the card rests in. Persisted, so it comes back where the
/// reader last put it.
enum FloatCorner: String { case topLeading, topTrailing, bottomLeading, bottomTrailing }

struct FloatingViewPreview: View {
    /// Recent deliveries, newest first. The card pages through them.
    let deliveries: [FloatingDelivery]
    /// How many of them the reader has not opened yet.
    let unreadCount: Int
    /// Which ones are unread (by id), for the per-page dot.
    let unreadIDs: Set<String>
    @Binding var index: Int
    /// Keep the card clear of the bar at the top and the keys at the bottom.
    var topInset: CGFloat
    var bottomInset: CGFloat
    var onOpen: (FloatingDelivery) -> Void
    var onClose: () -> Void

    @AppStorage("floatCorner") private var cornerRaw = FloatCorner.bottomTrailing.rawValue
    @AppStorage("floatLarge") private var large = false
    @State private var move: CGSize = .zero
    @State private var pageShift: CGFloat = 0
    /// What THIS drag is, decided once when it starts and kept until the
    /// finger lifts. Re-deciding every frame flipped a diagonal drag between
    /// "page" and "move", snapping the card back and forth (Jian: "dragging
    /// the small window causes flickering").
    private enum DragMode { case page, move }
    @State private var dragMode: DragMode?
    @State private var loading = true

    private var size: CGSize { large ? CGSize(width: 280, height: 210) : CGSize(width: 190, height: 146) }
    private let barHeight: CGFloat = 26
    private let margin: CGFloat = 10
    private var current: FloatingDelivery? {
        deliveries.indices.contains(index) ? deliveries[index] : deliveries.first
    }

    var body: some View {
        GeometryReader { g in
            let rest = position(for: FloatCorner(rawValue: cornerRaw) ?? .bottomTrailing, in: g.size)
            // The card's top-left in GLOBAL space, for "did the drag start on
            // the title bar" — the drag itself is measured globally (below).
            let origin = g.frame(in: .global).origin
            let cardTop = CGPoint(x: origin.x + rest.x - size.width / 2, y: origin.y + rest.y - size.height / 2)
            card
                .frame(width: size.width, height: size.height)
                // ONE drag, two meanings: sideways on the picture pages
                // between deliveries (Jian: "swipe within it"); anything else
                // — or any drag starting on the title bar — moves the card.
                .gesture(
                    // GLOBAL, not local: the card moves with the finger, so a
                    // translation measured in the card's own (moving) space
                    // fed back on itself — the card fought the finger
                    // (flicker) and under-counted the drag (390pt of finger
                    // read as 218), snapping back to its corner.
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { v in
                            if dragMode == nil {
                                // Decide on a real direction, not the first
                                // few points of finger wobble.
                                guard hypot(v.translation.width, v.translation.height) >= 12 else { return }
                                dragMode = isPaging(v, cardTop: cardTop) ? .page : .move
                                KBLog.record("float drag \(dragMode == .page ? "page" : "move") start=\(Int(v.startLocation.x - cardTop.x)),\(Int(v.startLocation.y - cardTop.y)) t=\(Int(v.translation.width)),\(Int(v.translation.height)) size=\(Int(size.width))x\(Int(size.height)) n=\(deliveries.count)")
                            }
                            if dragMode == .page { pageShift = v.translation.width } else { move = v.translation }
                        }
                        .onEnded { v in
                            let mode = dragMode ?? (isPaging(v, cardTop: cardTop) ? .page : .move)
                            dragMode = nil
                            KBLog.record("float drag end \(mode == .page ? "page" : "move") t=\(Int(v.translation.width)),\(Int(v.translation.height)) predicted=\(Int(v.predictedEndTranslation.width)),\(Int(v.predictedEndTranslation.height))")
                            if mode == .page {
                                let step = v.translation.width + v.predictedEndTranslation.width * 0.2
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    if step < -40, index < deliveries.count - 1 { index += 1 }
                                    else if step > 40, index > 0 { index -= 1 }
                                    pageShift = 0
                                }
                                return
                            }
                            // Where the FINGER let go decides the corner;
                            // momentum only nudges, capped. Adding a share of
                            // predictedEndTranslation outright let a release
                            // that slowed or pulled back (prediction pointing
                            // backwards: t=+132 predicted=-67, measured) fling
                            // the card back to where it started — "dragging
                            // doesn't work".
                            let fling = { (t: CGFloat, p: CGFloat) in max(-80, min(80, (p - t) * 0.15)) }
                            let x = rest.x + v.translation.width + fling(v.translation.width, v.predictedEndTranslation.width)
                            let y = rest.y + v.translation.height + fling(v.translation.height, v.predictedEndTranslation.height)
                            let corner: FloatCorner = (y < g.size.height / 2)
                                ? (x < g.size.width / 2 ? .topLeading : .topTrailing)
                                : (x < g.size.width / 2 ? .bottomLeading : .bottomTrailing)
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                cornerRaw = corner.rawValue
                                move = .zero
                            }
                        }
                )
                // Gesture BEFORE position: its coordinates are then the
                // card's own, so "started on the title bar" means what it says.
                .position(x: rest.x + move.width, y: rest.y + move.height)
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: large)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("floating preview")
    }

    /// Sideways on the picture = page; on the bar, or mostly vertical = move.
    private func isPaging(_ v: DragGesture.Value, cardTop: CGPoint) -> Bool {
        guard deliveries.count > 1 else { return false }
        let onBar = v.startLocation.y - cardTop.y > size.height - barHeight
        return !onBar && abs(v.translation.width) > abs(v.translation.height)
    }

    private func position(for c: FloatCorner, in area: CGSize) -> CGPoint {
        let left = margin + size.width / 2
        let right = area.width - margin - size.width / 2
        let top = topInset + margin + size.height / 2
        let bottom = area.height - bottomInset - margin - size.height / 2
        switch c {
        case .topLeading: return CGPoint(x: left, y: top)
        case .topTrailing: return CGPoint(x: right, y: top)
        case .bottomLeading: return CGPoint(x: left, y: max(top, bottom))
        case .bottomTrailing: return CGPoint(x: right, y: max(top, bottom))
        }
    }

    private var card: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let d = current {
                        preview(d)
                            .id(d.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .offset(x: pageShift * 0.35)
                            .allowsHitTesting(false)
                    }
                    // A plain SwiftUI layer over the preview owns every touch
                    // on the card, so no embedded UIKit view (a web page's
                    // scroll view, the player) can grab the drag.
                    Color.clear.contentShape(Rectangle())
                    // Unread count, always in view: the reason to look.
                    if unreadCount > 0 {
                        Text("\(unreadCount) unread")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.hopAttention, in: Capsule())
                            .foregroundStyle(.black)
                            .padding(6)
                            .accessibilityIdentifier("float unread")
                    }
                }
                .contentShape(Rectangle())
                bar
            }
            .background(Color.hopSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.hopGlow.opacity(0.35), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture(count: 2) { large.toggle() }
            .onTapGesture { if let d = current { onOpen(d) } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(current.map { "Open \($0.item.label)" } ?? "Deliveries")
            .accessibilityValue("\(index + 1)/\(deliveries.count) · \(unreadCount) unread")

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close preview")
        }
    }

    private var bar: some View {
        HStack(spacing: 5) {
            if let d = current {
                if unreadIDs.contains(d.id) {
                    Circle().fill(Color.hopGlow).frame(width: 6, height: 6)
                }
                Text(d.item.label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if deliveries.count > 1 {
                Text("\(index + 1)/\(deliveries.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("float position")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: barHeight)
        .background(Color.hopPill)
    }

    @ViewBuilder private func preview(_ d: FloatingDelivery) -> some View {
        switch d.kind {
        case .image:
            ArtifactImageView(url: d.url, loading: $loading)
        case .video:
            ArtifactPlayerView(url: d.url, muted: true, showsControls: false)
        case .page:
            // Laid out at a phone-ish width, then scaled into the card, so a
            // page previews as a page rather than a narrow reflow.
            GeometryReader { g in
                let w: CGFloat = 390
                let scale = g.size.width / w
                ArtifactWebView(url: d.url, loading: $loading, topInset: 0, interactive: false)
                    .frame(width: w, height: g.size.height / scale)
                    .scaleEffect(scale, anchor: .topLeading)
            }
        }
    }
}
