# PLAN — the planning-and-implement loop's queue

The loop reads this file, refines the top item into a concrete round,
implements it with the repo's conventions (probe-verify, gated suites,
deploy, STATUS), then updates this file. Jian reorders freely.

## 1. Re-entry size inconsistency (STUDIED 2026-07-28, fix pending)

Measured: PTY sizes across the fleet are heterogeneous — 51×49 where a
phone claimed, 76-78×24 default-ish elsewhere, and a 24-row grid
UNDERFILLS a phone that fits ~49. On entry the attach claim (2.5s idle
rule) decides everything: agent typed recently → claim refused → the
phone renders the peer/default size (pan mode or underfill); agent idle
→ claim wins → correct size. Same session, different minute, different
result. Candidate fixes, in order of promise:
- A SIZE CHIP in the chrome when drawn grid ≠ fitted ("76×24 · theirs")
  with one-tap Take size / Fit width — turns silent inconsistency into
  visible state with an exit.
- Claim RETRY: when the refusing typist goes idle past the window,
  re-claim automatically (needs care: never fight an active desk).
- The underfill case (grid rows ≪ fitted): consider centering or
  opportunistic claim even when cols fit.

## 2. Full-bleed polish on device
Jian to judge rows-under-status-text clearance (40pt) on hardware;
adjust if the top row kisses the clock on the real island.

## 3. Peek/tip placement sanity under the new top geometry
PeekTip popover position after full-bleed; arrowEdge choices.

## 4. (space intentionally left for Jian's next reports)
