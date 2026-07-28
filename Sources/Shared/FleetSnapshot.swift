import Foundation

/// The fleet, reduced to what a Home Screen glance needs. Written by the app
/// on every session refresh, read by the widget's timeline provider — the
/// app group's UserDefaults is the wire. Compiled into BOTH targets from
/// Sources/Shared, so the shape cannot drift between writer and reader.
struct FleetSnapshot: Codable {
    static let suite = "group.io.zhoulab.hop.spike"
    static let key = "fleetSnapshot"

    var updatedAt: Date
    var wanting: Int
    var total: Int
    var rows: [Row]

    struct Row: Codable, Hashable {
        /// The routing key — hop://session/<internalName> deep links.
        var internalName: String
        var name: String
        var attention: Bool
        var live: Bool
        var tagline: String
    }

    static func load() -> FleetSnapshot? {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FleetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.suite)?.set(data, forKey: Self.key)
    }
}
