import SwiftUI
import TipKit

// The app's best interactions are deliberately invisible — the pill swipe,
// the chrome strip, the long-press peek — which makes them undiscoverable by
// the same stroke. TipKit is the native answer: a hint that appears once,
// waits to be used or dismissed, and never returns. A web app would need a
// hand-rolled coach-marks layer and a place to persist "seen"; here both are
// the OS's job.

struct PeekTip: Tip {
    var title: Text { Text("Hold for a peek") }
    var message: Text? {
        Text("Long-press any session to read its whole screen without opening it.")
    }
    var image: Image? { Image(systemName: "eye") }
}

/// Auto-hide is opt-in (⋯ → Auto-hide menu) — someone who turned it on
/// asked for the trade, but the way back (a tap on the top strip) is still
/// invisible by design. Teach it ONCE, interactively: the tip appears the
/// first time chrome actually auto-hides and is dismissed by doing the
/// thing it teaches (rule .chromeSummoned donated on every summon tap), so
/// the first hide becomes the practice run.
struct ChromeSummonTip: Tip {
    static let chromeSummoned = Event(id: "chromeSummoned")
    var title: Text { Text("Controls hide themselves") }
    var message: Text? {
        Text("Tap the top of the screen any time to bring them back.")
    }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] {
        #Rule(Self.chromeSummoned) { $0.donations.count == 0 }
    }
}

extension View {
    /// popoverTip on exactly one element of a ForEach — a tip on EVERY tile
    /// would be a wall of popovers.
    @ViewBuilder
    func tipIf(_ condition: Bool, _ tip: some Tip) -> some View {
        if condition { self.popoverTip(tip) } else { self }
    }
}

enum HopTips {
    /// Configure once at launch. Under UI testing tips stay OFF — a popover
    /// is a hit-test wall in front of whatever a test tried to tap — unless
    /// the probe explicitly asks for them.
    static func configure() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-hop-show-tips") {
            try? Tips.resetDatastore()
            Tips.showAllTipsForTesting()
        } else if args.contains("-hop-ui-testing") {
            return
        }
        try? Tips.configure([.displayFrequency(.immediate),
                             .datastoreLocation(.applicationDefault)])
    }
}
