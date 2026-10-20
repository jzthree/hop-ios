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

    /// Never pops: the left-edge swipe opens the session drawer instead
    /// (Jian: "swipe from edge sometimes triggers returning to session
    /// view"). This recogniser is consulted on EVERY edge swipe, chrome and
    /// key bar included, so it is the one place that hears them all: it
    /// RELAYS — to the session's drawer inside a terminal, to the wall's
    /// drawer on the list. (A second, window-level edge pan for the wall lost
    /// to this one whenever UIKit asked this one first.) It must still refuse
    /// on the root: popping there breaks the next push.
    public func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        NotificationCenter.default.post(name: viewControllers.count > 1 ? .hopOpenDrawer : .hopOpenWallDrawer,
                                        object: nil)
        return false
    }
}
