import Foundation

// "Catch up" — hop web's ⌘G (utils/catchUp.ts): the next session with news
// for you. A question (the agent is waiting on you, or rang the bell) comes
// before a finished turn you have not read; inside each, the newest first.
// Parked sessions and ports never count, nor does the one on screen. `skip`
// holds the ones this run already visited — their read markers land a
// moment later, and without it two unread sessions bounced back and forth.

extension HopSession {
    /// 2 = a question for you, 1 = a finished turn not yet read, 0 = nothing.
    var newsRank: Int {
        // `attention` is the unseen bell, read against this phone's own
        // seen markers — what the wall's amber already means.
        attention ? 2 : phase == .doneUnread ? 1 : 0
    }
}

/// A question counts fleet-wide — scope is exactly what can hide one (the
/// wall's old "open the one that wants you" rule); an unread turn counts
/// only inside the scope you browse, so agents' workers don't flood "You".
private func hasNews(_ s: HopSession, current: String?, scope: SessionScope) -> Bool {
    !s.isPort && !s.parked && !s.archived && s.internalName != current
        && (s.newsRank == 2 || s.newsRank == 1 && matchesScope(s.createdBy, scope))
}

func nextSessionWithNews(_ sessions: [HopSession], current: String?,
                         scope: SessionScope = .all,
                         skip: Set<String> = []) -> HopSession? {
    sessions
        .filter { hasNews($0, current: current, scope: scope) && !skip.contains($0.internalName) }
        .max { a, b in
            a.newsRank != b.newsRank ? a.newsRank < b.newsRank : a.lastActivityAt < b.lastActivityAt
        }
}

/// How many sessions besides `current` have news — the catch-up chip's count.
func newsCount(_ sessions: [HopSession], current: String?, scope: SessionScope = .all) -> Int {
    sessions.filter { hasNews($0, current: current, scope: scope) }.count
}

/// One run of catch-up taps: they walk forward, and a pause of a minute
/// starts a fresh run (the web's catchUpVisitedRef).
@MainActor enum CatchUpRun {
    private static var keys: Set<String> = []
    private static var at = Date.distantPast

    /// The session to open next, or nil when all caught up. Asks the model
    /// to switch to it.
    @discardableResult
    static func advance(_ model: AppModel, from current: String?) -> HopSession? {
        if Date().timeIntervalSince(at) > 60 { keys = [] }
        at = Date()
        if let current { keys.insert(current) }
        guard let next = nextSessionWithNews(model.sessions, current: current,
                                             scope: model.swipeScope, skip: keys) else { return nil }
        keys.insert(next.internalName)
        model.requestedSession = next.internalName
        return next
    }
}
