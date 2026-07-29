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

## 8. (space for Jian's next reports)
