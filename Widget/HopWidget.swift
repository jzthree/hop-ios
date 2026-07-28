import SwiftUI
import WidgetKit

// The fleet on the Home Screen — the purest native advantage this app has
// over its web sibling: hop's state, visible without opening anything.
// Small says whether anything wants you; medium names the sessions.
//
// Deliberately self-contained: the palette is restated here rather than
// importing app sources, because an extension compiles its own world and
// dragging UIKit-adjacent files across that boundary is how widget builds
// rot. FleetSnapshot (Sources/Shared) is the one shared file — the wire
// format must not fork.

private extension Color {
    static let wSurface = Color(red: 0x0d / 255, green: 0x11 / 255, blue: 0x17 / 255)
    static let wGlow = Color(red: 0xa8 / 255, green: 0x55 / 255, blue: 0xf7 / 255)
    static let wAttention = Color(red: 0xf0 / 255, green: 0xa5 / 255, blue: 0x3a / 255)
    static let wLive = Color(red: 0x35 / 255, green: 0xd4 / 255, blue: 0x7a / 255)
    static let wDead = Color(red: 0xd9 / 255, green: 0x5a / 255, blue: 0x6b / 255)
}

struct FleetEntry: TimelineEntry {
    let date: Date
    let snapshot: FleetSnapshot?
}

struct FleetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FleetEntry {
        FleetEntry(date: .now, snapshot: FleetSnapshot(
            updatedAt: .now, wanting: 1, total: 12,
            rows: [.init(name: "Orion", attention: true, live: true,
                         tagline: "Improving the session switcher"),
                   .init(name: "Solstice", attention: false, live: true,
                         tagline: "Fixing terminal issues")]))
    }

    func getSnapshot(in context: Context, completion: @escaping (FleetEntry) -> Void) {
        completion(FleetEntry(date: .now, snapshot: FleetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FleetEntry>) -> Void) {
        // The app reloads timelines whenever the fleet materially changes;
        // the 30-minute horizon only bounds staleness when the app hasn't
        // run — the entry itself notes how old it is.
        let entry = FleetEntry(date: .now, snapshot: FleetSnapshot.load())
        completion(Timeline(entries: [entry],
                            policy: .after(.now.addingTimeInterval(30 * 60))))
    }
}

struct FleetSmallView: View {
    let entry: FleetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.wGlow)
                Text("hop")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Spacer()
            }
            Spacer()
            if let snap = entry.snapshot {
                if snap.wanting > 0 {
                    Text("\(snap.wanting)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.wAttention)
                    Text(snap.wanting == 1 ? "wants you" : "want you")
                        .font(.footnote)
                        .foregroundStyle(Color.wAttention)
                } else {
                    Text("\(snap.total)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("all quiet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("open hop once")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FleetMediumView: View {
    let entry: FleetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "hare.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.wGlow)
                Text("hop")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                Spacer()
                if let snap = entry.snapshot {
                    Text(snap.wanting > 0
                         ? "\(snap.wanting) want\(snap.wanting == 1 ? "s" : "") you"
                         : "all quiet")
                        .font(.caption2)
                        .foregroundStyle(snap.wanting > 0 ? Color.wAttention : .secondary)
                }
            }
            if let snap = entry.snapshot, !snap.rows.isEmpty {
                ForEach(snap.rows.prefix(4), id: \.self) { row in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(row.attention ? Color.wAttention
                                  : row.live ? Color.wLive : Color.wDead)
                            .frame(width: 5, height: 5)
                        Text(row.name)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                        Text(row.tagline)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("Open hop once to fill this in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

struct FleetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FleetEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium: FleetMediumView(entry: entry)
            default: FleetSmallView(entry: entry)
            }
        }
        .containerBackground(Color.wSurface, for: .widget)
    }
}

struct HopFleetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HopFleet", provider: FleetProvider()) { entry in
            FleetEntryView(entry: entry)
        }
        .configurationDisplayName("Fleet")
        .description("Your sessions at a glance — and who wants you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HopWidgetBundle: WidgetBundle {
    var body: some Widget {
        HopFleetWidget()
    }
}
