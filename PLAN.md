# PLAN — the planning-and-implement loop's queue

The loop reads this file, refines the top item into a concrete round,
implements it with the repo's conventions (probe-verify, gated suites,
deploy, STATUS), then updates this file. Jian reorders freely.

## 1. [SOLVED 2026-07-31 at the root] Re-entry size inconsistency

RESOLVED (iteration 228). The hole was the third wake state: socket
SURVIVED the idle -> we pinged for liveness and checked nothing else,
while a backgrounded phone silently adopts whatever grid the desk
elects (the deferred-adopt grace requires .active). Reopening worked
only because a fresh attach claims DELIBERATELY. Now one invariant --
enforceFit() -- holds at every edge: foreground + on screen + not
observing => the grid DRAWN equals the grid that FITS, re-asserted on
wake (immediately and again at 1.2s) and on keyboard settle. Its twin
rule, from Jian the same day: NOTHING resizes while nobody is looking
(userIsLooking gates every outbound resize; wire-witness proved the old
code sent two resizes from a backgrounded phone). Regression tests:
testWakeReclaimsTheSizeAfterAForeignResize, testBackgroundingSendsNoResize.

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

## 6. [RE-ARMED 2026-07-31 — needs a fresh device verdict] Keyboard-switch size nondeterminism
UPDATE (iteration 228): the settle verifier described below was WEAKER
than anyone noticed — it sent a POLITE resize a typing peer could
refuse, and it skipped the peer-held case entirely, which is precisely
the case a keyboard switch lands you in. It now routes through
enforceFit(), so a settle mismatch claims deliberately like every other
edge. Jian's verdict on 273+ decides whether this closes.

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

## 37. [DONE 2026-07-30] The blip rule: silence for brief drops
Jian: lock/unlock flashed "two lines of red text." Root: the
coordinator FED disconnect text into the terminal — pre-banner legacy
that also polluted scrollback forever. All disconnect feeds removed
(the gone screen carries permanent reasons; the banner carries
transient ones), and the banner+dim now sit behind a 1.2s grace
measured from the OUTAGE'S START (the first grace attempt reset per
state-update and could never mature — marker-traced). A blip shows
NOTHING; a real outage gets the countdown banner. Verified with the
upgraded drop hook (HOP_DEV_DROP_WS_COUNT sustains an outage by
killing follow-up reconnects pre-join — a post-join kill makes a
blip-train, which the grace rightly silences; that distinction cost
three probe cycles and is the whole point).

## 38. [DONE 2026-07-30] Web-sheet sweep: rename in-terminal + origin move
Jian: "missing rename — review the main hop web version." Sweep of
the web session sheet found TWO gaps: every session verb was
wall-only (nothing inside the terminal), and origin refile ("Move to
user/agent sessions", POST /api/sessions/origin) existed NOWHERE in
the app. Now: the terminal ⋯ has a Session section — Rename, Edit
tagline, Move to folder ▸, Move to You/Agents, Park (dismisses), Kill
(confirmed, dismisses) — and both wall menus carry Move to
You/Agents. E2E: origin round-trips user→agent→user on the live
daemon; permanent UI test asserts the terminal menu carries the
verbs. Sheet items verified covered: full screen (row tap), fork,
agent access, park/unpark, rename, tagline, origin, folders.

## 39. [DONE 2026-07-30] Toolbar summary overlap
Jian: the sentence overlapped the toolbar buttons on device.
Principal slot now renders ONLY the compact numeric form ("21 · quiet
· 1 parked") — short enough that overlap is impossible; VoiceOver
still hears the full sentence. (ViewThatFits measured its own
proposal, not its neighbors' appetite — device font scaling made the
sentence win while overlapping.)

## 40. [FIX + INSTRUMENT SHIPPED 2026-07-30 — awaiting one bad trace]
Re-entry size STILL often wrong (Jian, on 260)
The remaining machinery all works (probe-proven repeatedly), so the
suspect is upstream: the wake claim reading CACHED fitted dims from
the pre-lock layout — a deliberate claim with stale dims WINS the
election with the wrong size, and nothing corrects it until the next
layout-changing event. Fix shipped: sendAttachClaim forces a
synchronous layout pass first (SwiftTerm re-fits CURRENT bounds,
sizeChanged fires, THEN we read). And the wake trace is now
RELEASE-visible through the KBLog ring: every claim, active_size,
snapshot, fastPaint and epoch lands in Copy diagnostics.
JIAN'S MOVE if it happens again: the moment a terminal wakes wrong,
⋯ → Server & account → Copy diagnostics, paste it here — the wake
lines name the exact actor (stale claim dims / foreign adopt / fast
paint / no claim at all) and the next fix is surgical.

## 41. [DONE 2026-07-30] Copy chip: real element, real accessibility
The PLAN-32 caveat closed: the chip now hosts on the WINDOW — above
both opaque boundaries (the terminal's subtree and the SwiftUI
hosting view) — so it's reachable by VoiceOver and tappable by
identity in tests (the coordinate-tap workaround is gone; the e2e
taps buttons["Copy selection"] and the marker still witnesses the
copied word).

## 42. [DONE 2026-07-30] List facelift + agentic screenshots
Jian: the list "is not using the screen real estate efficiently —
hide it or do a face lift"; and "examples would be better if they are
agentic." Facelift chosen over hiding (the list uniquely carries
taglines, swipe actions and grouping): time inline on the name line
(the trailing column spent a gutter on four characters), subheadline
name, caption2 tagline, 2-line preview with tighter chrome, 5pt row
insets — ~9 visible rows where ~5.5 fit before, nothing dropped. The
demo screenshot fleet was rebuilt AGENTIC (⏺/⎿ transcript content,
task-shaped taglines: PR review, flaky-test hunt, perf audit…) and
both wall shots retaken under a top-10 cleanliness guard (the denser
list shows more rows, so the guard grew with it; his brand-new
hopboard session kept topping the fleet mid-shoot and had to be
waited out).

## 43. [GATED on Jian's hopboard repo going public] Link hopboard
Jian: hopboard (Flowboard iOS voice keyboard) is going public; hop-ios
should link it for dictation — "free, better than Apple native, close
to paid app level." When the repo URL exists: a README paragraph in
the keyboard section (hop keyboard for terminal symbols + hopboard
for voice), and possibly an in-app pointer. A dead link is worse than
none, so this waits for the URL.

## 44. [DONE 2026-07-30] The half-open socket: input readiness is real now
Jian: "the terminal shows, but it doesn't take any user input — go
back and re-enter and it works"; and readiness should be VISIBLE
without typing. Root: after idle the socket dies SILENTLY (no close
event), the screen paints from cache, the dot says live, and
sendInput's completion IGNORED errors — keystrokes vanished into a
corpse. Three fixes: (1) send failures now tear the socket down and
RE-BUFFER the discovering keystroke (PendingInput replays it after
reconnect — nothing typed is ever lost); (2) every foreground wake
pings the socket with a 2.5s deadline — a corpse feeds the normal
reconnect machinery BEFORE the first keystroke, and the blip-grace
keeps a healthy pong invisible; (3) the pill dot breathes (sonar)
while connecting and is solid green only when verified — the ready
signal Jian asked for, made trustworthy rather than added. E2E:
HOP_DEV_HALFOPEN simulates the silent death (generation-orphaned
close); the probe types into the corpse and the daemon's screen shows
the full line after auto-recovery. (First run of the probe passed
FALSELY against a normal drop — the hook hadn't landed; caught by
timestamp discipline.)

## 45. [INSTRUMENT SHIPPED 2026-07-30 — awaiting one failed dictation]
Dictation insertion + transcription UI
Half (a), ours: every UITextInput door now logs to the KBLog ring —
insertText (length + prefix), setMarkedText, unmarkText,
deleteBackward, and an explicit insertDictationResult. The one
uninstrumentable door is replace(_:withText:) (public-not-open in
SwiftTerm): a failed insertion whose trace shows NO door firing
convicts replace() by elimination. Ring grown to 240 lines so the
trace survives the walk to Copy diagnostics. En route, a REAL bug in
the fresh half-open fix: errored sends re-buffered only the burst's
FIRST key (daemon read "eho half-ok"); now every errored payload
re-buffers regardless of generation. JIAN'S MOVE: next failed
flowboard insert → Copy diagnostics immediately; the ti.* lines (or
their silence) name the door.
Half (b), the transcript-preview one-tap-insert UI: not in this
repo's history — likely flowboard's surface. Jian to confirm
ownership before anything is built here.
## 46. NATIVE passkeys (upgrade path) — GATED twice
Shipped today: "Sign in with Face ID" on the sign-in screen, which runs
the WebAuthn ceremony in a WKWebView against the daemon's existing
/api/passkeys/login and adopts the tunnel_session cookie it sets. That
works TODAY with no entitlement and no hop2 change, and it uses the same
passkey already enrolled in hop web (same rpID).

The NATIVE version (ASAuthorizationPlatformPublicKeyCredentialProvider —
the system Face ID sheet, no web view at all) needs two things neither of
which is Orion's to grant:
1. **Associated Domains entitlement** `webcredentials:hop.zhoulab.io`,
   which needs a provisioning profile carrying that capability — i.e. the
   Apple Developer account gate that also blocks the widget and
   TestFlight (DVTDeveloperAccountManagerAppleIDLists still empty).
2. **hop must serve** `/.well-known/apple-app-site-association` with
   `{"webcredentials":{"apps":["5AD7QB9795.io.zhoulab.hop.spike"]}}` —
   a hop2 change (Solstice). The daemon serves no AASA today (verified).
When both land, the UI stays and PasskeyLogin.swift's middle is replaced.

## 47b. [DONE 2026-08-02] THE DIGEST — "what should I pay attention to" (Jian, 2026-08-02)
Jian's ask, verbatim in shape: a ONE-PAGE digest when he comes back to
the hub, priority-ordered, each item TAPPABLE to open the session it
refers to. Runs ~4x/day, one landing ~07:00 so it is ready before he
wakes (~8-9). Cost must be negligible against his $200 subscription.
Model: prefers Claude (GPT-5 xhigh "sometimes very very slow"), but
wants TWO digests at first to compare, then keep the winner.

WHERE IT RUNS: not on the phone. The daemon host already has the
screens, the bell history, and a Claude subscription — a scheduled job
there writes the digest; the phone only RENDERS it. That keeps the
phone cheap, works while it is asleep, and means the 07:00 run does not
depend on the phone being awake. Delivery: a new daemon endpoint
(hop2 change — Solstice) or, to stay inside this repo's boundary, a
file the host writes that the app fetches.

INPUT (cheap by construction): per session, the LAST screen we already
cache (FleetCache/screensRaw), the tagline, bellSeq/attention, parked
state, and last activity. That is ~24 short screens — a few thousand
tokens, four times a day. Do NOT send scrollback.

OUTPUT CONTRACT (strict, so the UI can render it and cost stays flat):
JSON, max ~8 items, each {internalName, headline (<=70 chars), why
(<=140 chars), urgency: needs-you|blocked|finished|fyi}. One page means
the model must RANK and DROP, not summarise everything.

"WHAT HAVE I ALREADY SEEN": approximate with what the app already
tracks — markSeen()/seenBellSeq per session, plus lastActivityAt. An
item whose bellSeq has not moved since he last opened that session is
demoted. Jian: "it might be hard to gauge what i have looked at but do
your best" — so this is a heuristic, stated as one in the UI copy.

UI: a card at the top of the wall, collapsed to the top 3 with a
"more" disclosure; each row taps straight into its session (the
requestedSession path already exists). Dismiss marks it read; the next
digest replaces it.

TWO-MODEL COMPARE (first week only): generate with Claude and with the
other model, tag each digest with its author, and show them as two
tabs so Jian can pick. Then delete the loser.

DECISIONS FOR JIAN: (a) is a hop2 endpoint acceptable, or should the
host write a file the app polls; (b) confirm 4x/day + 07:00 anchor;
(c) confirm the one-page cap is ~8 items.

## 48b. [FIX SHIPPED 2026-08-03 — Jian's device decides] Interleaved lines — the double reflow
SHIPPED (iteration 236): the local terminal is PINNED to the PTY's grid
while a peer holds the size. SwiftTerm re-fits on every bounds change
(layoutSubviews) and font change (resetFont), both internal and not
overridable — so the pin corrects inside our layoutSubviews override, in
the SAME layout pass, before a frame is drawn at the wrong grid. With the
font scaled to the elected columns the wrong fit differs only in ROWS,
and row-only resizes do not rewrap — so the rewrap churn that interleaved
wrapped lines stops. Probe: foreign 100x30 adopted, keyboard cycled twice
(the churn that reliably corrupted), screenshot clean end to end.

Found while fixing: a keystroke's claim was computed from the SCALED
font, so typing "claimed" the peer's own size — a keystroke that changed
nothing. Claims now propose the NATURAL fit (the user's chosen font), and
the confirming active_size is recognised as ours via lastUserClaim even
though the live fitted dims still describe the scaled font at that
moment. The chip tap claims naturally too.

Jian, precisely: "two lines of text show in one in a randomly
interspersed way." That is not a paint artifact (updateFullScreen would
have cured it) — it is a REFLOW artifact. Character-level interleaving of
two source lines on one row is what happens when a WRAPPED line is
re-joined at a width that is not the width it was wrapped at.

MECHANISM (evidence, iteration 234): adoptForeign resizes the local
terminal to the peer's width; SwiftTerm then re-fits the terminal to the
VIEW on its next layout pass and resizes it back. Two reflows of the same
buffer at two different widths — and every wrapped line in the scrollback
is re-joined and re-split by both. The font auto-scale is supposed to make
SwiftTerm's re-fit land on the SAME column count, which would make the
second reflow a no-op; when it lands a column or two off, the thrash is
visible as interleaved text.

FIX DIRECTION: stop the second reflow rather than repainting after it.
Either (a) suppress SwiftTerm's automatic re-fit while a peer holds the
grid (the local terminal should be the PTY's size, full stop), or (b)
make the scaled font land EXACTLY on the elected column count and assert
it — the fitNudges convergence loop already exists for observer mode and
should be doing this. Verify by resizing a scratch session's PTY under a
phone with wrapped text on screen and diffing the rendered rows.

## 50b. Digest everywhere (Jian: "too good to miss")
- [DONE 2026-08-04] DESKTOP: DigestCard.tsx on the hop web wall (hop2
  c7a88d2, authored by Orion at Jian's explicit ask — own file, one
  2-line insertion into the switcher). Same digest.json, same reading
  contract: datelines, unread dots, per-edition dismiss; story clicks
  route through handleTap so dead sessions start in place.
- NEXT: terminal version. Cheapest honest shape: `hop digest` reading
  the same served file (or the assets path directly on the host) and
  printing summary + datelines with urgency colours; zero new state.
  hop CLI is Solstice's surface — hand off or ask Jian which.
- Read/unread on iOS shipped (build 290): glow dot per story, opening
  clears it, ledger keyed to the edition, unread count in the ⋯ menu.

## 49b. Digest follow-ups (not blocking)
- Two-model compare: DIGEST_MODEL=sonnet writes a second file; show both
  as tabs for a week, keep the winner. Opus already looks clearly better.
- "What have I already seen": demote items whose bellSeq has not moved
  since that session was last opened (markSeen already tracks this).
- Cost/quality watch: one Opus run over ~24 sessions takes ~6 minutes and
  is read later, which is the whole reason Opus is affordable here.

## 46b. (space for Jian's next reports)

## 47. [DONE 2026-07-30] Case-folded name resolution at the boundaries
hop2 e4bdd86 made every daemon surface that addresses a session BY
NAME case-insensitive (exact-first, unique-fold fallback, ambiguous
folds resolve to nothing). Mirrored client-side as
resolveSessionName() — internal-exact, display-exact, internal-fold,
display-fold, ambiguity = miss — applied at the THREE choke points
every outside door funnels through: the warm requestedSession /
pendingOpen onChange handlers (which previously pushed the RAW string
with no resolution at all — even an exact display name dead-ended
warm) and the cold openPendingSession poll. Internal lookups (pill
swipe, fork, list taps) never touch the resolver; daemon-minted names
stay exact. Five unit tests pin the contract incl. the ambiguity
rule; e2e launches with the internal fixture name case-mangled and
lands in the terminal.

## 48. Landscape chrome: summonable, not banished
PROBLEM: `if chromeShown, !landscapePhone` — the chrome bar can NEVER
appear in landscape. Back works (edge swipe), the banner works, but
the ⋯ menu, session verbs, find, copy, the pill swipe, the readiness
dot and the state-conditional Reconnect row are all unreachable
without rotating to portrait. The new Reconnect placement sharpens
it: during a landscape outage the menu row that exists FOR that
moment cannot be reached.
EVIDENCE: TerminalScreen.swift:451 (the suppression), :378 (rotation
force-hides); Jian's rule ("landscape gives every point to the
terminal") shaped the suppression — but the rule is about DEFAULT
state, and the top-strip tap that summons chrome in portrait already
proves summoned-chrome is compatible with it.
ROUND SKETCH: let the existing top-strip tap summon the SAME pill in
landscape (slimmer padding), auto-hide after 3s as in portrait, keep
rotation's force-hide. No new UI — one condition and a padding
variant. Probe: landscape screenshot with chrome up; UI test rotates,
taps the strip, asserts Terminal actions exists, rotates back.

## 49. Omnisearch parity: the filter should reach what's ON the screens
PROBLEM: the wall filter matches name/cwd/runningApp/tagline only
(SessionFilter.swift:110-113). The web's omnisearch (hop2 f6e6852,
44ad888) reaches session CONTENT — on the phone, "which session
mentioned the failing test?" has no answer short of opening each one.
EVIDENCE: filterSessions source; FleetCache already persists
screensRaw for every session — the content corpus is sitting on
device, so this needs NO new daemon calls and works offline from the
cache.
ROUND SKETCH: extend filterSessions to also match the screens store
(strip ANSI via the existing parser output, lowercase contains), show
a "found on screen" affordance in the row (the web's "Found in
output" equivalent — e.g., the matching line as the preview snippet),
unit tests over fixture screens, probe screenshot of a content-hit
row. Guard: never fetch previews server-side for this — local corpus
only (the wall-filter content-search incident is the cautionary tale).
