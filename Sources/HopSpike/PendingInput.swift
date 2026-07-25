import Foundation

// Keystrokes typed during an outage. hop's web client buffers and replays
// these rather than dropping them, and the age cap is what makes that safe:
// a reconnect replays what you just typed, while a command from a minute ago
// never lands mid-something-else. On a phone — where blips are the norm —
// losing a whole command to a two-second tunnel hiccup is the worse failure.
//
// Pure, because "did the stale entry actually get dropped" is exactly the kind
// of thing that breaks silently and is never noticed until it ruins something.
struct PendingInput {
    static let maxAge: TimeInterval = 15
    static let maxEntries = 200

    private var entries: [(data: String, at: Date)] = []

    var isEmpty: Bool { entries.isEmpty }

    /// Oldest entries fall off first: during a long outage the newest
    /// keystrokes are the ones still worth sending.
    mutating func append(_ text: String, at date: Date) {
        guard !text.isEmpty else { return }
        entries.append((text, date))
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    /// Empties the buffer, returning what should be replayed (in order, as one
    /// message) and how many were too old to send.
    mutating func drain(now: Date) -> (replay: String, dropped: Int) {
        let queued = entries
        entries = []
        let fresh = queued.filter { now.timeIntervalSince($0.at) <= Self.maxAge }
        return (fresh.map(\.data).joined(), queued.count - fresh.count)
    }
}
