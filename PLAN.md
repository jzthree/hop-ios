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

## 2. [CLOSED 2026-07-29 — Jian: "good as is, very close to the clock
but that is fine"] Full-bleed polish on device

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

## 6. [VERDICT 2026-07-29: STILL BROKEN — item 11 now actionable] Keyboard-switch size nondeterminism
Jian: switching keyboards sometimes leaves the grid too small for the
space left. A settle verifier now runs 700ms after each keyboard-frame
burst: if the drawn grid disagrees with the current fit (and we hold
the claim), it re-asserts, and a layout pass recomputes SwiftTerm's own
fit. Needs Jian's device verdict; if it persists, instrument the
keyboard-frame sequence with markers next.

## 7. [CLOSED 2026-07-29 — Jian: "scrolling seems fixed"] Claude fullscreen-mode scrolling
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

## 11. [INSTRUMENT SHIPPED 2026-07-29 — awaiting one bad trace from Jian]
Keyboard-frame instrument
KBLog: an 80-line ring recording every keyboardWillChangeFrame (endY,
height, duration), every fit (cols×rows + view bounds), every settle
verdict (ok/MISMATCH with view height) — surfaced in Account -> Copy
diagnostics, so the phone needs no env vars or cables. Permanent UI
test guards the whole path (record -> copied text). JIAN'S MOVE: next
time a keyboard switch leaves the terminal too small, immediately
Settings -> Server & account -> Copy diagnostics and paste it into
this session — the trace names whether the keyboard frame, SwiftUI's
avoidance (bounds), or SwiftTerm's grid went stale, and the fix
follows from which.

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
URL via DEBUG marker. DEVICE VERDICT 2026-07-29: "almost works!" —
the Dock icon appeared but ?room= no longer enters a session (the
daemon serves the hub at /, which ignores the query). FIXED same day:
the donation is now the canonical path /s/<internalName>/ (what
buildSessionPath pushes; verified 200 + __HOP_SESSION__ injection);
incoming leg parses the path with ?room= as legacy fallback. Needs one
more two-device try.

## 14. [DONE 2026-07-28] Share a session's screen
"Share screen…" (ShareLink, subject = session name) beside Copy screen
in both context menus, same copyableScreen gating and trimming.
Probe-verified visually (docs/screens/share-sheet.png) and by a
permanent UI test — which surfaced a trap now recorded: the sheet's
actions are CELLS (actionGroupCell) in the app's own tree, not
Buttons, so app.buttons["Copy"] matches nothing while the sheet is
plainly on screen.

## 15. [DROPPED 2026-07-29 — Jian: no BT keyboard] Hardware-keyboard commands (iPad / BT keyboard)
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

## 17. [DONE 2026-07-29 — client side] Wake-flash
Marker instrument (HOP_WAKE_MARKER, wakeMark lines at connect epochs,
fastPaint, joined, snapshot, claim, every active_size) traced the
mechanism in one run: foreign ADOPT at t+440ms, claim at t+842ms (the
400ms fresh-open delay), OURS 21ms later. Two fixes: reconnect claims
now go at 0ms (the delay was for fresh-open keyboard layout only), and
foreign adopts within 3s of a foreground connect are DEFERRED 1.2s —
the claim's confirm cancels them (probe-proven: DEFERRED → OURS, no
foreign render; a lost race adopts late). RESIDUAL: the fast paint
still renders ~RTT at the PTY's foreign dims (must, for legibility);
zero-flash needs attach-carries-size daemon-side — noted in
HOP2-NOTES. Jian verdict wanted: is the flash gone in practice?
## 18. [RE-GATED 2026-07-29 — the sign-in didn't stick] Widget build
Attempted: unparked the target, device build failed "No Accounts" for
BOTH targets. Diagnosis, not guesswork: `defaults read com.apple.dt.
Xcode DVTDeveloperAccountManagerAppleIDLists` shows an EMPTY account
list (IDE.Identifiers.Prod = ()); the 5AD7QB9795 team entry present is
a stale remnant of an old session. Re-parked; builds green again.
JIAN: Xcode → Settings → Accounts → "+" → sign in with the Apple ID
owning team 5AD7QB9795, and check the account actually appears in the
list afterward. The next loop round re-attempts automatically.

## 19. [SAME GATE as 18 — empty Xcode account list] TestFlight attempt (Jian: "sure if you can")
Blocked previously at ASC key AUTH (issuer 254072af…). With Xcode now
signed in, try the Xcode-account path: create the App Store Connect
app record if the account can, archive, upload. If the key still gates
uploads, report exactly what credential is missing rather than
retrying blind.

## 20. [DONE 2026-07-29 — audit CLEAN] Rename-robustness audit
Every store already keys internalName: seen bells (seed + prune +
attention), notified bells (+ threadIdentifier + clear), lastKnown,
previews/screens, Spotlight, handoff path, hop:// links, widget rows.
Open-by-name resolves internalName OR display name (notification taps,
Siri, HOP_DEV_OPEN). The open terminal's title follows session_renamed
live (renamedTitle override). Search matches display names — correct,
users type what they see. One regression test now pins the discipline
(bell rings through a rename; display-name markers are dead keys).
Also this round: make uitest resolves the fixture from internalName
(iteration 191's fix — same principle, harness side).

## 21. [SHIPPED 2026-07-29] The hop keyboard
Built as answered: HopBoardView via UIResponder.inputView, toggled
from the accessory bar (⌨ key, past the fold) and from the board's
own ⌨ key back to the system keyboard (the dictation/emoji hatch).
Standard three-plane layout (abc/123/#+=) so muscle memory transfers;
mono face; hop theme; FIXED 232pt height — the keyboard-switch resize
lottery (item 6) cannot fire while it's up. Board text routes through
typedText — the same ctrl/alt-arming path as system typing, so
accessory-ctrl + board letter = a control chord. Sticky preference
(UserDefaults hopBoard). Unit test proves every printable ASCII char
reachable; permanent UI test covers toggle, all three planes, and the
hatch; screenshots in docs/screens. Jian: refinement reports welcome
(key sizes, missing chords, a dedicated ctrl row?).
## 22. [DONE 2026-07-29] Instant launch: the wall from cache
FleetCache persists the daemon's RAW JSON (sessions + previews +
screens) on each successful refresh (20s throttle; the save after a
cache paint goes immediately); bootstrap loads it before the first
network round-trip and paints the wall at first frame — gated on a
credential existing (no session content over a login screen), with
authenticated set optimistically (a real 401 still flips to login).
Raw JSON, not Codable mirrors: the load path re-runs the exact live
parsers (HopSession(json:), TileInk.decode), so cache and live can
never drift, and attention recomputes against CURRENT seen markers.
signOut deletes the file. Unit test round-trips through the live
parsers + corrupt-file safety; permanent UI test relaunches with
HOP_DEV_CACHE_ONLY=1 (network path disabled) and the wall still
paints.
## 23. [DONE 2026-07-29] Shortcuts verbs: Reply and New Session
ReplyToSessionIntent (session entity + text, via the QuickReply
throwaway socket, honest failure dialog) and NewSessionIntent (create,
refresh, land in the terminal) — both registered in HopShortcuts with
Siri phrases. Proven by an e2e unit test that runs the intents' own
perform() against the REAL daemon: NewSessionIntent creates a scratch
session, ReplyToSessionIntent sends "echo intent-ok", the daemon's
preview shows the text arrived, teardown kills the scratch. make test
now forwards the daemon token (TEST_RUNNER_HOP_DEV_TOKEN) so the
round-trip runs in every suite instead of skipping.
## 24. [GATED with 18 — same provisioning] Live Activity: "wants you"
on the Lock Screen
Problem: a bell today is a notification that scrolls away; the state
"an agent is waiting on you NOW" is exactly what Live Activities and
the Dynamic Island exist for.
Evidence: attention state + fleetStatusLine already computed; the
widget extension (parked) is the same target a Live Activity ships in.
Sketch (build when the Xcode account lands): ActivityKit activity
started on first wanting session, updated with count + names, ended
when quiet; Dynamic Island compact = the wanting count.

## 25. [DONE 2026-07-29] Optimistic local echo
Ported hay's optimisticEcho.ts as a pure Swift struct — faithful to
the model its comments earned (printable-only pending; TUI-redraw
guard; in-order consume with foreign stop; 800ms expiry; two-strike
mismatch clear). All seven web test cases transliterated and green,
including the composer-repaint and coalesced-SGR regressions. Wired
with the web's exact gating (sole controller, not collab — tracked
from collab events; reset on connect, snapshot, close, eligibility
loss); echo feeds before the wire in deliver, reconcile filters
before every output feed (raw still reaches mode detection).
Permanent UI probe: typed into a scratch session with echo live, the
daemon saw single characters ("echo zq", never "eecc") — an echo
leaked into the send path would double on the wire. Jian's verdict:
typing feel on cellular.
## 26. [MEASURED 2026-07-29 — fix NOT needed; instrument stays] Feed-burst frame drops
The frame-gap monitor (CADisplayLink, records stalls >max(50ms, 3
frames) to the KBLog ring beside >32KB feed sizes; runs whenever a
terminal is attached, near-free) answered the question the momentum
code's clamp only suspected: a 60,000-line seq flood plus a 30,000
long-line flood produced FOUR gaps total — 72, 62, 135, 60ms — and
ZERO feeds over 32KB. The daemon already chunks output small and
SwiftTerm keeps up; coalescing would be machinery without a measured
problem. The instrument is permanent: any future regression shows up
in the same Copy-diagnostics trace as the keyboard events.
## 27. [DONE 2026-07-29] The hop keyboard in landscape
232pt portrait / 150pt landscape via UITraitVerticalSizeClass
observation (iOS 17 API — the deprecated override tripped the
zero-warning strict gate first); spacing tightens, rows compress
through the fillEqually column. Anti-lottery guarantee holds PER
ORIENTATION. Permanent test asserts real compression: the q key
measures <80% of its portrait height after rotation.
## 28. [DONE 2026-07-29] Fleet-cache file protection
fleet-cache.json now writes [.atomic, .completeFileProtectionUnlessOpen]:
terminal content on disk is readable only with the device unlocked
(which is when the app reads it); background refreshes can still
WRITE a fresh cache while locked via the asymmetric path. Cache
round-trip unit tests unchanged and green.
## 29. [DONE 2026-07-29] Drift round: the daemon's new refusal, and the
hole it left
Upkeep sweep (all green: 88 unit / 23 UI / strict 0 / TSan 0 races /
device current) surfaced hop2 drift: d1e76ce stops the daemon
inventing sessions for unknown names (404 on attach — raw-handshake
verified; the iOS classifier already maps it to the gone UI). Building
the pin-test EXPOSED the residual: killed-but-REMEMBERED names still
resurrect on attach (the test's tap brought GoneProbe back from the
dead). Client-side fix shipped: a wall list that came from the launch
cache is HEARSAY — attaching from it verifies existence first (the
reconnect path's check, now shared); a live-list attach pays zero
extra latency (liveListSeen). Also fixed en route: HOP_DEV_CACHE_ONLY
now inerts ALL refreshes, not just bootstrap's (the periodic tick was
overwriting the cache mid-test). Permanent test: cold launch into a
killed cached session lands on "Session ended", and the daemon's LIST
(the honest witness — /preview remembers the dead without
resurrecting) stays phantom-free. Daemon residual recorded in
HOP2-NOTES.

## 30. [DONE 2026-07-29] Fork session
Same-day parity with hop2 f6e6852. forkSession() on the model (POST,
reads the response's internalName, surfaces hop's own error text);
"Fork session" in the tile menu, the row menu, and the terminal's ⋯
sheet — forking mid-conversation switches you to the fork while the
original runs on. E2E against the real daemon: scratch created in
/tmp, forked, fork present in the refreshed list WITH the inherited
cwd, both killed, zero leftovers verified. UI suite asserts the menu
offers it (presence only — tapping would fork the live fixture).
Omnisearch (same commit) verified web-UI-only: no /api/sessions/search
changes.
## 31. [DONE 2026-07-29] Folders: Jian's filing, now on the phone
HopSession.folderId + a folders store (parsed from /api/sessions, in
the FleetCache too so the cached wall keeps its sections); the wall's
grouping is a three-way Arrange picker — Recent / By project / By
folder (old Bool preference migrates); "By folder" renders his folder
names as sections in daemon order, Unfiled last, dead folderIds land
in Unfiled rather than vanishing. Context menus gain "Move to ▸"
(folders + Unfiled + "New folder…" which creates-and-files in one
gesture). Read-mostly by design: rename/delete stay web-side.
E2E: ProbeFolder created on the real daemon, scratch filed in,
folderId round-tripped through refresh, unfiled, both deleted —
fleet verified clean (his three live folders are DATA, untouched).
UI: By folder renders a real live folder-name section
(fixture-tolerant); Move-to presence asserted in the long-press menu;
probe-shot docs/screens/folders-wall.png shows Research/Softwares
sections live.
## 32. [DONE 2026-07-29] Select and copy, no modes
Jian: "select and copy is not working — in mobile web we choose
between scrolling and selecting; we shouldn't have to in native." We
don't: PRESS-AND-HOLD selects the word under the finger (a hold is
never a scroll), SwiftTerm's own handles extend it, our scroll pan
already yielded to active selections, and a hop-styled Copy chip in a
FIXED top-trailing slot copies text CAPTURED at chip-creation (immune
to whatever later clears the live selection). What was broken: the
whole SwiftTerm copy UI is UIMenuController — dead on modern iOS; and
in mouse sessions double-tap goes to the app, so no path existed.
Battle scars recorded in comments: recognizer-set mutation mid-touch
resets the gesture; UIEditMenuInteraction + SwiftTerm's UITextInput
fight (menu churned the keyboard, cleared selection under itself);
canPerformAction is public-not-open; the system text-input menu
(Paste/Select/Select All) still appears at the selection and coexists
with the chip. E2E: pressed "1030" in a scratch, tapped the chip's
slot, marker witnessed exactly "1030". A11y caveat: the chip lives
under the SwiftUI hosting boundary and misses the element tree —
VoiceOver follow-up queued.

## 33. [DONE 2026-07-29] Production-grade disconnect handling
The reconnect story is now told, not implied: a socket drop shows a
banner under the pill — "Connection lost — retrying in Ns" counting
down, then "Reconnecting…", with a NOW button that skips the backoff
(reconnectToken, the same road the menu's Reconnect takes). The frozen
content dims and desaturates while disconnected and restores on
reconnect; the pill's status dot was already honest (amber). All fed
by onRetryState from the coordinator's own scheduleRetry — the UI
shows the real schedule, not a guess. Verified deterministically via
HOP_DEV_DROP_WS (DEBUG: hard-drops the socket once, N seconds after
first connect — the permanent probe hook this class of UX needed):
permanent test asserts banner appears after the drop and CLEARS on
auto-recovery, session usable after; screenshot in docs/screens.
Existing machinery already covered: input buffering with honest
replay-or-discard, offline wall banner, cached-wall launch, foreground
reconnect, dead-session gone-screen.
## 34. [DONE 2026-07-29] Keyboard-top margin
Root-caused, not tuned: SwiftUI's keyboard avoidance already clears
the FULL keyboard frame including the accessory bar riding on it, so
the app's own accessoryInset padding (46pt when the keyboard is up)
was pure double-counting — a dead band above the key bar exactly the
bar's height. Removed, along with its keyboardWillChangeFrame
machinery; screenshot-verified flush (last row directly above esc,
nothing hidden). The keyboard-DOWN home-indicator clearance is a
separate mechanism and stays.
## 35. [CLOSED 2026-07-29 — keep both, integrated] Back button vs ⋯ menu
Jian accepted keep-both with the refinement that the menu must feel
integrated, not overlapping. Done in the same round: the ⋯ is no
longer a floating circled button — a hairline seam and a bare glyph
inside the pill, the chevron's visual sibling at the other end.
## 36. [DONE 2026-07-29] Origin declaration (drift: hop2 18f86ce)
The daemon now files undeclared Bearer-token callers as AGENT (probe
sessions like SelectProbe under User is what prompted it — our own
harness's fingerprints). Contract read: explicit x-hop-actor wins;
cookie auth infers user; token auth without x-hop-via infers agent.
The app now DECLARES x-hop-actor: user on every write (post + fork) —
everything this app does is a human's act. On-device cookie auth was
never at risk; the declaration makes it true on every auth path and
future-proof. E2E: a session created over Bearer auth lands
createdBy=user on the live daemon (fails without the header). Also
skimmed e150138 (records durability + web full-screen demotion): no
client-facing API change.

## 37. (space for Jian's next reports)
