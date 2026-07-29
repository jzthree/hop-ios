# PLAN — the planning-and-implement loop's queue

The loop reads this file, refines the top item into a concrete round,
implements it with the repo's conventions (probe-verify, gated suites,
deploy, STATUS), then updates this file. Jian reorders freely.

## 1. Re-entry size inconsistency (STUDIED; chip SHIPPED; wake-path next)

REFINED by Jian: the trigger is RETURN FROM IDLE — phone backgrounds,
comes back, the open terminal is wrong. The size chip (below) now makes
the state visible with a one-tap exit; the remaining work is the wake
sequence itself: on foreground reconnect, verify fittedCols/Rows aren't
stale from the pre-background keyboard state when the snapshot's re-fit
runs, and consider an automatic re-claim once the refusing typist goes
idle. Fast paint is NOT the culprit (its resize is snapshotLanded-gated,
verified by reading).

Measured: PTY sizes across the fleet are heterogeneous — 51×49 where a
phone claimed, 76-78×24 default-ish elsewhere, and a 24-row grid
UNDERFILLS a phone that fits ~49. On entry the attach claim (2.5s idle
rule) decides everything: agent typed recently → claim refused → the
phone renders the peer/default size (pan mode or underfill); agent idle
→ claim wins → correct size. Same session, different minute, different
result. Candidate fixes, in order of promise:
- [DONE 2026-07-28] SIZE CHIP: "90×44 — take mine" appears top-trailing
  whenever a peer/default size holds the grid; tap claims; a refusal
  re-arms it (probe-verified against a held 90×44).
- [DONE 2026-07-28] Claim RETRY: while foreground with a peer-held
  grid, the attach intent re-asserts every 5s; the server grants when
  the holder lapses. Probe-verified end to end: chip under a live hold,
  no tap, healed and cleared once the hold ended. Backgrounded phones
  run no retries, so nothing steals from a pocket.
- [CLOSED by tracing 2026-07-28] Underfill: a smaller-than-fitted grid
  still reaches the adopt→chip→retry path via the refusal rebroadcast
  (snapshot re-fits to ours first, so the rebroadcast always mismatches
  the drawn grid). No separate machinery needed.

## 2. Full-bleed polish on device
Jian to judge rows-under-status-text clearance (40pt) on hardware;
adjust if the top row kisses the clock on the real island.

## 3. [VERIFIED FINE 2026-07-28] Peek/tip placement under new geometry
Probe-shot: PeekTip anchors below the first tile, arrow up, no island
collision. No change needed.

## 4. [DONE 2026-07-28] Two views, one button (Jian's directive)
Back chevron restored; the in-title switch menu REMOVED entirely (title
is a plain label). The pill swipe stays — direct manipulation, not
chrome. Native scroll bounce killed (the phantom scrolled-to-the-end
animation on drags that rightly don't move the terminal).

## 5. [DONE 2026-07-28] Tap-to-click for mouse-on sessions
Claude's "(click)" pills are reachable: a tap below the chrome strip in
a session that ASKED for mouse reporting sends a real SGR press+release
at that cell (terminal-testified: cat -v echoed ^[[<0;26;15M/m). Plain
shells never see clicks; the coast-brake and chrome strip keep their
taps.

## 6. [FIRST PASS 2026-07-28] Keyboard-switch size nondeterminism
Jian: switching keyboards sometimes leaves the grid too small for the
space left. A settle verifier now runs 700ms after each keyboard-frame
burst: if the drawn grid disagrees with the current fit (and we hold
the claim), it re-asserts, and a layout pass recomputes SwiftTerm's own
fit. Needs Jian's device verdict; if it persists, instrument the
keyboard-frame sequence with markers next.

## 7. Claude fullscreen-mode scrolling (NEEDS REPRO DETAIL)
"Some sessions still have scrolling issues in claude fullscreen mode."
Need one detail from the device: in that mode, does the transcript not
move at all, move the wrong amount, or move the local viewport instead?
And is it a session where the chip shows a foreign size? The sink
logging added in the double-scroll round should name the path taken.
**Partly addressed by the viewport pin** (Jian: "the native scroll bar
should never show up — our terminal element should always fit and the
terminal scrolling is handled in hop"): isScrollEnabled=false,
indicators off, contentInsetAdjustmentBehavior=.never. UIKit can no
longer move the content at all — no keyboard scroll-to-visible, no
inset fiddling, no indicator flash. Whatever scrolling issue remains
after this build is by definition in OUR sink routing, which the sink
log will name.

## 8. [DONE 2026-07-28] Toolbar summary truncates ("21 sessions · nothing…")
Fixed with two pure formatters (fleetSummaryLine / fleetSummaryCompact)
and ViewThatFits in the principal slot: the sentence when it fits, the
numbers when it doesn't ("21 · quiet · 1 parked", "18/21 · 2 want you
(+1)"). VoiceOver always gets the full sentence via accessibilityLabel.
Probe-shot: docs/screens/toolbar-compact.png — complete, no ellipsis.

## 9. [DONE 2026-07-28] Copy a session's screen from the wall
"Copy screen" in both tile and row context menus (shown only when the
screens store has the session); pasteboard gets the grid with trailing
padding stripped (copyableScreen, unit-tested). Permanent UI test
verifies the action's content via a DEBUG marker file — the runner
CANNOT read the pasteboard back (iOS 16 background-paste privacy
silently denies it; two red runs proved this), recorded in tools
traps.

## 10. [DONE 2026-07-28 — and reframed] Agent input vs the size election
Reading rooms.ts dissolved the premise: the daemon ALREADY lets a
deliberate human claim win outright (`user: true` on resize — the flag
the web sends on explicit switches). iOS never sent it. Now it does
(attach-when-foreground, chip tap, touch/keystroke reclaims; the 5s
retry stays polite). E2E: a deliberate open took the size from a
live-typing 100×30 hold instantly — the hold's own socket witnessed
`active_size 51×49`. The re-entry lottery should be OVER for every
deliberate act. HOP2-NOTES.md carries the record plus the one residual
daemon question (agent WS input still counts as typist recency for
recency-based claims only; low stakes now).

## 11. [CONDITIONAL on Jian's item-6 verdict] Keyboard-frame instrument
If the too-small-after-keyboard-switch persists on 224: a marker
harness logging each keyboardWillChangeFrame (target frame, duration),
the accessoryInset decision, the resulting fitted dims, and the grid
900ms later — one switch session's worth of markers names the exact
misfire. Build only after the verdict.

## 12. [SHIPPED first half 2026-07-28] Touch-to-autofit + web-mobile size model
Jian: "a single touch should trigger autofit; hop-ios is not supporting
non-autofit terminals gracefully — follow how the hop web terminal
handles it in mobile mode." Web study (hay/apps/web/src/App.tsx):
auto-fit is the DEFAULT everywhere; foreign active_size is never
rendered in fit mode; fit-on-type reclaims on the first keystroke
(500ms throttle, forced past the resize dedupe); Manual mode is the
opt-in that renders the remote's true size, native font, overflow+pan.
iOS already had fit-on-type (deliver) and Manual-equivalents (peer
adopt+pan, Fit to width); what was missing was TOUCH as intent.
DONE: reclaimOnUserIntent() — an approved single tap (the one choke
point every tap passes: gestureRecognizerShouldBegin; touchesEnded
misses recognized taps, becomeFirstResponder fires only when
unfocused — both probe-proven), plus mouse clicks, plus every
keystroke. E2E: under a live 100×30 hold, chip up, zero claims until
one tap sent our 51×49 down the wire (HOP_CLAIM_MARKER harness,
scratch session, excised).
REMAINS (Jian's device verdict): whatever "not graceful" still means
on hardware once touch-claims land — candidates: underfill rendering
(small foreign grid leaves dead space), the observe-only Fit-to-width
floor (4pt texture), chip visibility.

## 13. [DONE 2026-07-28] Handoff: pick the session up at the desk
Shipped: the open terminal donates an NSUserActivity
(io.zhoulab.hop.session.handoff, eligibleForHandoff, webpageURL =
server + "?room=<internalName>" — the param App.tsx reads); SwiftUI
invalidates it on leave. Incoming leg routes the same activity type on
another hop-running device (QuickActions), so iPhone->iPad continues
natively while Mac picks up in Safari. handoffURL() unit-tested
(escaping, hostless-server nil); permanent UI test asserts the donated
URL via DEBUG marker. ON JIAN'S DEVICE CHECKLIST: open a session on
the phone near the Mac — Safari's Handoff icon should appear in the
Dock and open the same session.

## 14. [DONE 2026-07-28] Share a session's screen
"Share screen…" (ShareLink, subject = session name) beside Copy screen
in both context menus, same copyableScreen gating and trimming.
Probe-verified visually (docs/screens/share-sheet.png) and by a
permanent UI test — which surfaced a trap now recorded: the sheet's
actions are CELLS (actionGroupCell) in the app's own tree, not
Buttons, so app.buttons["Copy"] matches nothing while the sheet is
plainly on screen.

## 15. Hardware-keyboard commands (iPad / BT keyboard)
Problem: with a physical keyboard attached the app offers nothing
beyond raw typing — no next/prev session, no find, no way back to the
wall without touching glass.
Evidence: the web has hotkeys (e.g. its Ctrl+Q kill parity binding);
neighborSession() already computes the switch ring; UIKeyCommand is
idle native surface.
Sketch: Cmd+] / Cmd+[ next/prev session via neighborSession, Cmd+F
find-in-scrollback, Cmd+W back to the wall; unit-test the keyCommands
table; feel needs Jian's hardware verdict (does he use a BT keyboard?).
LOWER priority until Jian confirms the use case.

## 16. [DONE 2026-07-29] Swift 6 migration — the named baseline is retired
Zero strict-concurrency warnings, and `make strict` is now RED on any.
The five sites, each fixed by stating a runtime fact the code already
relied on: HopTermView.deinit invalidates its timers inside
MainActor.assumeIsolated (a UIView deinits on main — now checked);
Coordinator conforms via @preconcurrency TerminalViewDelegate
(SwiftTerm's protocol is nonisolated, the witnesses run on main); the
typing-settle Timer callback wraps in assumeIsolated (run-loop timers
fire on main, the closure type just couldn't say so). No behavior
change; full suites green after.

## 17. (space for Jian's next reports)
