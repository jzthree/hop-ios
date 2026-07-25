import Foundation

// Pure list-shaping, extracted from the view so it can be unit-tested:
// which sessions a scope shows, and how a filter query matches.
enum SessionScope: String, CaseIterable {
    case user = "You", agent = "Agents", all = "All"
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
