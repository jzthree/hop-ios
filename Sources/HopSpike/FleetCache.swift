import Foundation

// Instant launch (PLAN 22): the last known wall, persisted. iOS kills this
// app constantly, and every return from the graveyard rendered a BLANK wall
// for a full network round-trip — seconds of empty screen in an app built
// for glancing. The fix is a cache of the three stores the wall renders
// from, written on refresh and read at init, so the wall paints at first
// frame and the live refresh replaces it moments later.
//
// Shape choice: the RAW JSON the daemon sent, not Codable mirrors — loading
// re-runs the exact same parsers (HopSession(json:), TileInk.decode), so
// the cache can never drift from the live path. Staleness self-labels: row
// ages come from lastActivityAt.
//
// The cache holds session names and screen CONTENT, so signOut deletes it.
enum FleetCache {
    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        return dir.appendingPathComponent("fleet-cache.json")
    }

    struct Payload {
        var sessions: [[String: Any]]
        var previews: [String: String]
        var screens: [String: [String: Any]]
    }

    static func save(_ p: Payload, to url: URL = defaultURL) {
        let dict: [String: Any] = ["sessions": p.sessions,
                                   "previews": p.previews,
                                   "screens": p.screens]
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func load(from url: URL = defaultURL) -> Payload? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = obj["sessions"] as? [[String: Any]] else { return nil }
        return Payload(sessions: sessions,
                       previews: (obj["previews"] as? [String: String]) ?? [:],
                       screens: (obj["screens"] as? [String: [String: Any]]) ?? [:])
    }

    static func delete(at url: URL = defaultURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
