import Foundation

// Pure list-shaping, extracted from the view so it can be unit-tested:
// which sessions a scope shows, and how a filter query matches.
enum SessionScope: String, CaseIterable {
    case user = "You", agent = "Agents", all = "All"
}

/// Group label for a session: the first couple of path segments under home
/// ("~/Code/hop2"), matching how the web switcher buckets a fleet. Sessions in
/// a project root and its subdirectories land together.
func projectKey(_ cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "Other" }
    var shortened = cwd
    if let r = cwd.range(of: #"^/(Users|home)/[^/]+"#, options: .regularExpression) {
        shortened = "~" + cwd[r.upperBound...]
    } else if cwd == "/root" {
        shortened = "~"
    } else if cwd.hasPrefix("/root/") {
        shortened = "~" + cwd.dropFirst("/root".count)
    }
    let home = shortened.hasPrefix("~")
    let parts = shortened.drop(while: { $0 == "~" || $0 == "/" })
        .split(separator: "/").map(String.init)
    let kept = Array(parts.prefix(home ? 2 : 3))
    if kept.isEmpty { return home ? "~" : "/" }
    return (home ? "~/" : "/") + kept.joined(separator: "/")
}

/// Sessions bucketed by project, most-recently-active bucket first.
func groupSessionsByProject(_ sessions: [HopSession]) -> [(label: String, rows: [HopSession])] {
    var buckets: [String: [HopSession]] = [:]
    for s in sessions { buckets[projectKey(s.cwd), default: []].append(s) }
    return buckets
        .map { (label: $0.key, rows: $0.value) }
        .sorted { a, b in
            let aa = a.rows.map(\.lastActivityAt).max() ?? 0
            let bb = b.rows.map(\.lastActivityAt).max() ?? 0
            return aa == bb ? a.label < b.label : aa > bb
        }
}

func filterSessions(_ sessions: [HopSession], scope: SessionScope, query: String) -> [HopSession] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    return sessions.filter { s in
        guard !s.isPort else { return false }
        switch scope {
        case .user: if s.createdBy == "agent" { return false }
        case .agent: if s.createdBy != "agent" { return false }
        case .all: break
        }
        guard !q.isEmpty else { return true }
        return s.name.lowercased().contains(q)
            || s.shortCwd.lowercased().contains(q)
            || s.runningApp.lowercased().contains(q)
            || s.tagline.lowercased().contains(q)
    }
}

/// Sessions that should raise a notification or badge: those wanting attention,
/// minus the one being watched right now. Notifying someone about the terminal
/// they are looking at is noise, and it inflates the badge for a session they
/// have already seen.
func alertable(_ sessions: [HopSession], openSession: String?) -> [HopSession] {
    sessions.filter { $0.attention && $0.internalName != openSession }
}

/// A 6-digit authenticator code, cleaned. Authenticator apps and password
/// managers hand over "123 456" or "123-456" often enough that pasting one
/// otherwise just fails, and the field is a number pad with no way to correct
/// it comfortably.
func sanitizedCode(_ raw: String) -> String {
    String(raw.filter(\.isNumber).prefix(6))
}
