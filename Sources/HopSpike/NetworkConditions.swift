import Foundation
import Network

// A web page polls at whatever rate it was written for. A native app can ask
// what it's connected to, and a phone spends most of its life on a cellular
// radio someone is paying for — with the session list refreshing every 5s and
// previews costing the daemon a render each, "whatever rate it was written
// for" is the app being a bad guest in a pocket.
//
// Low Data Mode in particular is an explicit instruction from the user; iOS
// surfaces it as `isConstrained` and expects apps to honour it.
@MainActor
final class NetworkConditions: ObservableObject {
    static let shared = NetworkConditions()

    @Published private(set) var isExpensive = false     // cellular / personal hotspot
    @Published private(set) var isConstrained = false   // Low Data Mode

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isExpensive = path.isExpensive
                self?.isConstrained = path.isConstrained
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.zhoulab.hop.spike.network"))
    }

    var sessionPollInterval: TimeInterval { pollInterval(expensive: isExpensive, constrained: isConstrained) }
    var previewPollInterval: TimeInterval? { previewInterval(expensive: isExpensive, constrained: isConstrained) }
}

/// How often to re-list sessions. Wi-Fi keeps the 5s that makes attention feel
/// immediate; cellular backs off; Low Data Mode backs off hard.
func pollInterval(expensive: Bool, constrained: Bool) -> TimeInterval {
    if constrained { return 30 }
    return expensive ? 12 : 5
}

/// How often to refresh the live previews, or nil to skip them entirely.
/// Previews are the expensive half — one daemon render per visible session —
/// and they are a nicety, unlike the list itself. Low Data Mode drops them.
func previewInterval(expensive: Bool, constrained: Bool) -> TimeInterval? {
    if constrained { return nil }
    return expensive ? 25 : 9
}
