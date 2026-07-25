import Foundation
import Network
import os

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
    /// Whether there's any usable path at all. "Your phone has no signal" and
    /// "hop is down" ask for completely different things from the user, and
    /// URLError's text ("A server with the specified hostname could not be
    /// found") points at the wrong one.
    /// HOP_DEV_OFFLINE=1 forces this false: the offline UI is otherwise
    /// unreachable in a simulator, which borrows the host's network.
    @Published private(set) var isOnline =
        ProcessInfo.processInfo.environment["HOP_DEV_OFFLINE"] != "1"

    /// Low Power Mode is the same kind of instruction as Low Data Mode — the
    /// user has explicitly asked every app to do less — and a 5s poll with a
    /// render per visible session is exactly what that means.
    @Published private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// Bumped whenever the route changes underneath us — wifi to cellular,
    /// cellular to wifi, a dead path coming back. A socket does not survive
    /// that, and `isOnline` cannot report it: walking out of wifi range onto 5G
    /// leaves the path satisfied the whole way, so nothing else in the app ever
    /// learns that every open connection just became dead weight.
    ///
    /// Without this the terminal waits out its backoff — up to 15 seconds of
    /// dead screen while the phone has had a working route the entire time.
    @Published private(set) var pathGeneration = 0

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let route = Route(satisfied: path.status == .satisfied,
                              wifi: path.usesInterfaceType(.wifi),
                              cellular: path.usesInterfaceType(.cellular),
                              wired: path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor in
                guard let self else { return }
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                if ProcessInfo.processInfo.environment["HOP_DEV_OFFLINE"] != "1" {
                    self.isOnline = path.status == .satisfied
                }
                // Only a real route change counts. NWPathMonitor also fires for
                // things that leave every existing connection working, and a
                // reconnect costs a fresh snapshot on someone's cellular.
                if route != self.route {
                    self.route = route
                    self.pathGeneration += 1
                    Logger(subsystem: "io.zhoulab.hop.spike", category: "network")
                        .info("route \(route.name, privacy: .public) (change \(self.pathGeneration))")
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.zhoulab.hop.spike.network"))
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
                }
            }
    }

    private struct Route: Equatable {
        let satisfied: Bool, wifi: Bool, cellular: Bool, wired: Bool
        var name: String {
            guard satisfied else { return "none" }
            return [wifi ? "wifi" : nil, cellular ? "cellular" : nil,
                    wired ? "wired" : nil].compactMap { $0 }.joined(separator: "+")
        }
    }
    private var route = Route(satisfied: false, wifi: false, cellular: false, wired: false)

    /// Low power folds into "expensive": a different signal, the same
    /// conclusion, so the interval table needs no extra branch.
    var sessionPollInterval: TimeInterval {
        pollInterval(expensive: isExpensive || isLowPower, constrained: isConstrained)
    }
    var previewPollInterval: TimeInterval? {
        previewInterval(expensive: isExpensive || isLowPower, constrained: isConstrained)
    }
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
