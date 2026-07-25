import Foundation

// The coast after a flick. Kept apart from the display link that drives it so
// the feel is a few numbers that can be argued with and tested, rather than
// constants buried in a frame callback.
//
// Everything is in POINTS PER FRAME at 60fps, matching the debt accumulator it
// feeds — which is what lets a remote app coast on wheel events exactly like
// our own viewport does.
struct ScrollMomentum {
    /// 0.94/frame ≈ UIScrollView's feel: a flick coasts for about a second.
    static let friction = 0.94
    /// Below a quarter point per frame there is nothing left to see.
    static let minVelocity = 0.25
    /// A flick, not the end of a slow careful drag. Releasing a drag that was
    /// already crawling should stop where you left it.
    static let flickThreshold = 60.0        // points per second

    private(set) var velocity = 0.0

    /// Returns whether this release was a flick worth coasting.
    mutating func start(pointsPerSecond: Double) -> Bool {
        guard abs(pointsPerSecond) >= Self.flickThreshold else {
            velocity = 0
            return false
        }
        velocity = pointsPerSecond / 60
        return true
    }

    /// One frame: the points to spend, or nil when the glide is over.
    mutating func step() -> Double? {
        guard abs(velocity) >= Self.minVelocity else { return nil }
        let step = velocity
        velocity *= Self.friction
        return step
    }

    mutating func stop() { velocity = 0 }

    /// How far a flick coasts in total — the geometric series, which is the
    /// honest way to ask "is this going to fly off to the far end of history".
    static func coastDistance(pointsPerSecond: Double) -> Double {
        guard abs(pointsPerSecond) >= flickThreshold else { return 0 }
        return (pointsPerSecond / 60) / (1 - friction)
    }
}
