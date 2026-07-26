import UIKit

// Keep the swipe back to the session list working when the navigation bar is
// hidden.
//
// UIKit ties the interactive pop gesture to the navigation bar: hide the bar
// and the gesture goes with it. That is fine for a screen with a visible back
// button, and wrong here — the terminal gave up its bar for terminal room, so
// the back button only exists inside chrome that is hidden by default. Without
// this, the way out of a session is: tap the top strip, then tap back. With
// it, the swipe every iOS user already knows still works.
//
// Extending UINavigationController is heavy-handed, but this app has exactly
// one stack, and the alternative — wrapping the whole hierarchy in a
// representable to reach the same recogniser — is more machinery for the same
// two lines.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    /// Only when there is somewhere to go back TO. Left unguarded, the gesture
    /// fires on the root and leaves the stack in a state where the next push
    /// does nothing.
    public func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
