import Foundation

// News for you on a session: a question (the agent is waiting on you, or
// rang the bell) outranks a finished turn you have not read. The drawer
// bolds these. (The catch-up button that walked through them went: with
// many sessions in an order you cannot steer, it was no help — Jian.)

extension HopSession {
    /// 2 = a question for you, 1 = a finished turn not yet read, 0 = nothing.
    var newsRank: Int {
        // `attention` is the unseen bell, read against this phone's own
        // seen markers — what the wall's amber already means.
        attention ? 2 : phase == .doneUnread ? 1 : 0
    }
}
