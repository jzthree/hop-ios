import SwiftUI

// Scheduled as a calendar — hop web's Calendar (utils/calendar.ts,
// CheckbacksPanel): check-backs sit on their days, a repeat on every day it
// runs (a frequent one as a band, "every 30 min"), and what was sent on the
// day it went. Condition-triggered ones (idle, a file, a command) have no
// time, so they are listed under the week. A phone has no room for seven
// columns of text, so the week is a strip of days and the picked day reads
// below it, the way the system Calendar does it.

/// More often than this, the times would crowd the day out: a band instead.
let calendarBandUnderMs: Double = 3 * 3_600_000

struct Occurrences: Equatable {
    var times: [Double]
    var band: Double?
}

extension Checkback {
    /// Firings in [from, to), ms — exact times, or a band (with its period)
    /// when too frequent to list. Mirrors the web's triggerOccurrences.
    func occurrences(from: Double, to: Double) -> Occurrences {
        if triggerKind == "at" { return Occurrences(times: at >= from && at < to ? [at] : [], band: nil) }
        guard triggerKind == "every", everyMs > 0 else { return Occurrences(times: [], band: nil) }
        let end = until > 0 ? min(to, until + 1) : to
        if everyMs < calendarBandUnderMs {
            return Occurrences(times: [], band: next < end && end > from ? everyMs : nil)
        }
        var times: [Double] = []
        var k = from <= next ? 0.0 : ((from - next) / everyMs).rounded(.up)
        var t = next + k * everyMs
        while t < end && times.count < 200 { times.append(t); k += 1; t = next + k * everyMs }
        return Occurrences(times: times, band: nil)
    }

    var isTimed: Bool { triggerKind == "at" || triggerKind == "every" }
}

/// Seven local midnights from the day of `first` (DST-safe: by the calendar).
func weekDays(from first: Date, calendar cal: Calendar = .current) -> [Date] {
    let start = cal.startOfDay(for: first)
    return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
}

/// One line on a day: a firing (pending), a send that happened (delivered),
/// or a band across the day.
struct DayEntry: Identifiable {
    enum Kind { case due, sent, band }
    let id: String
    let item: Checkback
    let at: Double          // ms; 0 for a band
    let kind: Kind
}

func dayEntries(_ items: [Checkback], day: Date, calendar cal: Calendar = .current) -> [DayEntry] {
    let from = day.timeIntervalSince1970 * 1000
    let to = (cal.date(byAdding: .day, value: 1, to: day) ?? day).timeIntervalSince1970 * 1000
    var out: [DayEntry] = []
    for c in items {
        if c.status == "pending" {
            let o = c.occurrences(from: from, to: to)
            if o.band != nil { out.append(DayEntry(id: c.id + "/band", item: c, at: 0, kind: .band)) }
            for t in o.times { out.append(DayEntry(id: "\(c.id)/\(Int(t))", item: c, at: t, kind: .due)) }
        } else if c.status == "delivered", c.doneAt >= from, c.doneAt < to {
            out.append(DayEntry(id: c.id + "/sent", item: c, at: c.doneAt, kind: .sent))
        }
    }
    return out.sorted { a, b in
        a.kind == .band ? b.kind != .band : b.kind == .band ? false : a.at < b.at
    }
}

struct CheckbackWeekView: View {
    let items: [Checkback]
    let nameFor: (String) -> String
    var onOpen: (String) -> Void
    var onCancel: (Checkback) -> Void
    @State private var weekStart = Calendar.current.startOfDay(for: Date())
    @State private var picked = Calendar.current.startOfDay(for: Date())

    private var days: [Date] { weekDays(from: weekStart) }
    private var untimed: [Checkback] { items.filter { $0.status == "pending" && !$0.isTimed } }

    var body: some View {
        List {
            Section {
                weekStrip
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            Section {
                let entries = dayEntries(items, day: picked)
                if entries.isEmpty {
                    Text("Nothing on this day.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(entries) { e in row(e) }
            } header: {
                Text(picked.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .textCase(nil)
            }
            if !untimed.isEmpty {
                Section("When something happens") {
                    ForEach(untimed) { c in
                        entryBody(time: c.whenText, c: c, muted: false)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { cancelButton(c) }
                    }
                }
            }
        }
    }

    private var weekStrip: some View {
        VStack(spacing: 8) {
            HStack {
                Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous week")
                Spacer()
                Text(rangeTitle).font(.subheadline.weight(.semibold))
                Spacer()
                Button { shift(7) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next week")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 6)
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { d in dayCell(d) }
            }
        }
    }

    private var rangeTitle: String {
        guard let a = days.first, let b = days.last else { return "" }
        let cal = Calendar.current
        if cal.isDate(a, inSameDayAs: cal.startOfDay(for: Date())) { return "This week" }
        return "\(a.formatted(.dateTime.month(.abbreviated).day())) – \(b.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func dayCell(_ d: Date) -> some View {
        let cal = Calendar.current
        let entries = dayEntries(items, day: d)
        let due = entries.filter { $0.kind == .due }.count
        let band = entries.contains { $0.kind == .band }
        let sent = entries.contains { $0.kind == .sent }
        let isPicked = cal.isDate(d, inSameDayAs: picked)
        let isToday = cal.isDateInToday(d)
        return Button { withAnimation(.easeOut(duration: 0.15)) { picked = d } } label: {
            VStack(spacing: 3) {
                Text(d.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(d.formatted(.dateTime.day()))
                    .font(.callout.weight(isToday || isPicked ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isPicked ? Color.white : isToday ? Color.hopGlow : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(isPicked ? Color.hopPurple : .clear, in: Circle())
                // What the day holds: a band as a bar, times as a count.
                HStack(spacing: 2) {
                    if band { Capsule().fill(Color.hopWorking.opacity(0.7)).frame(width: 10, height: 3) }
                    if due > 0 {
                        Text(due > 9 ? "9+" : "\(due)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.hopGlow)
                    } else if sent {
                        Circle().fill(Color.secondary.opacity(0.5)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d.formatted(.dateTime.weekday(.wide).day())), \(due) scheduled")
        .accessibilityAddTraits(isPicked ? [.isSelected] : [])
    }

    @ViewBuilder private func row(_ e: DayEntry) -> some View {
        let time: String = switch e.kind {
        case .band: "every \(spanText(e.item.everyMs))"
        case .sent: "sent \(clock(e.at))"
        case .due: clock(e.at)
        }
        let line = entryBody(time: time, c: e.item, muted: e.kind == .sent)
        if e.item.status == "pending" {
            line.swipeActions(edge: .trailing, allowsFullSwipe: true) { cancelButton(e.item) }
        } else {
            line
        }
    }

    private func entryBody(time: String, c: Checkback, muted: Bool) -> some View {
        Button { onOpen(c.session) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(time)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(muted ? Color.secondary : Color.hopGlow)
                    .frame(width: 74, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.message).font(.subheadline).lineLimit(3)
                        .foregroundStyle(muted ? Color.secondary : Color.primary)
                    Text(nameFor(c.session) + (c.createdBy == "agent" ? " · by the agent" : ""))
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cancelButton(_ c: Checkback) -> some View {
        Button(role: .destructive) { onCancel(c) } label: { Label("Cancel", systemImage: "xmark.circle") }
    }

    private func shift(_ n: Int) {
        let cal = Calendar.current
        guard let w = cal.date(byAdding: .day, value: n, to: weekStart) else { return }
        weekStart = w
        picked = cal.date(byAdding: .day, value: n, to: picked) ?? w
    }

    private func clock(_ ms: Double) -> String {
        Date(timeIntervalSince1970: ms / 1000).formatted(date: .omitted, time: .shortened)
    }

    private func spanText(_ ms: Double) -> String {
        let m = Int((ms / 60000).rounded())
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60) min"
    }
}
