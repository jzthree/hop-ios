import Foundation

// The coast after a flick. Kept apart from the display link that drives it so
// the feel is a few numbers that can be argued with and tested, rather than
// constants buried in a frame callback.
//
// Everything is per SECOND, and every step takes the elapsed time. That is not
// tidiness: CADisplayLink runs at up to 120Hz on a ProMotion phone, so a
// per-FRAME decay silently coasts twice as fast for half as long there — and
// the simulator, at 60Hz, would never show it.
struct ScrollMomentum {
    /// UIScrollView's own normal deceleration rate, which is expressed per
    /// MILLISECOND. Matching it is the point: the ask was for scrolling to
    /// feel like the rest of iOS, and this is the number the rest of iOS uses.
    static let decelerationRate = 0.998
    /// Below about a point per frame there is nothing left to see.
    static let minVelocity = 15.0           // points per second
    /// A flick, not the end of a slow careful drag. Releasing a drag that was
    /// already crawling should stop where you left it.
    static let flickThreshold = 60.0        // points per second

    private(set) var velocity = 0.0         // points per second

    /// Returns whether this release was a flick worth coasting.
    mutating func start(pointsPerSecond: Double) -> Bool {
        guard abs(pointsPerSecond) >= Self.flickThreshold else {
            velocity = 0
            return false
        }
        velocity = pointsPerSecond
        return true
    }

    /// One frame: the points to spend over `elapsed` seconds, or nil when the
    /// glide is over.
    mutating func step(elapsed: Double) -> Double? {
        guard abs(velocity) >= Self.minVelocity, elapsed > 0 else { return nil }
        let step = velocity * elapsed
        velocity *= pow(Self.decelerationRate, elapsed * 1000)
        return step
    }

    mutating func stop() { velocity = 0 }

    /// How far a flick coasts in total — the integral of the decay, which is
    /// the honest way to ask "is this going to fly off to the far end of
    /// history". Exponential decay never quite stops, so this is measured to
    /// the point where the glide is cut off.
    static func coastDistance(pointsPerSecond: Double) -> Double {
        guard abs(pointsPerSecond) >= flickThreshold else { return 0 }
        let decayPerSecond = -log(decelerationRate) * 1000
        let cutoff = pointsPerSecond > 0 ? minVelocity : -minVelocity
        return (pointsPerSecond - cutoff) / decayPerSecond
    }
}
