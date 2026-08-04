# hop-ios STATUS — owned by Orion (mobile track)

Division of labor: **Orion** (this repo, mobile) · **Solstice** (hop2, desktop).
Solstice: read-only for you; leave notes for me in hop2 commits or tell Jian.

> **Start here:** what needs *you* is in the three sections immediately below —
> the device checklist, then the decisions. Everything from "Reference" down is
> history: how things were built and why, kept because the reasoning is the
> useful part. The change log at the bottom is append-only.

## Mandate
1. **Spike first**: SwiftTerm + WS attach to a live hop session + native keyboard,
   built to Jian's iPhone. Keyboard-feel thesis validated on hardware before v1.
2. PWA web-push interim (manifest + SW + daemon push on bellSeq) in parallel.
3. APNs daemon endpoint only after the spike passes.
4. hop2 changes: minimal, separately committed.

## Where this stands right now

*(top rewritten at iteration 207 — the previous head was iteration-112-era:
it still discussed the TestFlight ISSUER key that has since failed AUTH, and
a device checklist whose size-election items were closed by builds 229-237.)*

**Build 271 is on the phone** (270 shipped mid-round; 271 carries the
suite-caught menu fix); gates green at last full run (93 unit, 30 UI
executed, strict zero) and the loop's queue is entirely verdict-bound —
nothing left is self-serviceable. Jian's standing word: deploy to the
phone IMMEDIATELY every round.

## Waiting on you — one batch, ten minutes with the phone

The five that decide recent work:
1. **Typing feel off wifi** (build 245+): the echo wait is gone in shells and
   prompts? In Claude's composer, does typed text ever flicker/vanish on
   repaint?
2. **The hop keyboard** (240, landscape 248): ⌨ on the key bar. Worth keeping?
   Key sizes, missing keys, want a ctrl row on the board itself?
3. **Instant launch** (242+): kill the app, reopen — wall there at first
   frame?
4. **Wake-flash** (237+): lock, wait, unlock into an open terminal — does the
   wrong-size flash still appear?
5. **Handoff retry** (236+ carries the /s/ path fix): session open near the
   Mac → Safari Dock icon → does it land IN the session now?

Standing: if a keyboard switch (system side) ever leaves the terminal too
small again — immediately ⋯ → Server & account → Copy diagnostics and paste
it here (238's flight recorder is in every build since).

Never answered, still wanted (one line each): does the coast/flick feel
right on the 120Hz screen; does the diagnostics `background:` line ever say
it RAN (decides APNs urgency); notification long-press reply on a SHELL
session; badge appearing and clearing; Low Data Mode degrading gracefully.

## The credentials gate (unblocks three queued features)

Xcode → Settings → Accounts → "+" → sign in with the Apple ID owning team
5AD7QB9795 — and confirm the account then APPEARS IN THE LIST (last
attempt left it empty: DVTDeveloperAccountManagerAppleIDLists shows
`IDE.Identifiers.Prod = ()`; the visible team entry is a stale remnant).
The moment it sticks, the loop auto-attempts: home-screen widget → 
TestFlight (cellular installs) → "wants you" Live Activity.

## Decisions that are yours
- **APNs**: `APNS-PLAN.md` has the whole daemon-side shape; client half
  shipped long ago. Yes/no is all it needs.
- **Archived sessions**: marked as stopped in the list, or transparent?

## Web-mobile parity matrix (re-audited 2026-07-25, after iteration 48)

| Feature | web mobile | iOS |
|---|---|---|
| Attach / live terminal | ✓ | ✓ |
| Session list, attention-first | ✓ | ✓ |
| Taglines / cwd / app badge / relative time | ✓ | ✓ |
| Filter by name/cwd/app/tagline | ✓ | ✓ |
| **Search session OUTPUT** (`/api/sessions/search`) | ✓ (palette) | ✓ (#40) |
| Origin scope user/agent/all | ✓ | ✓ |
| Create / rename / kill session | ✓ | ✓ |
| Find in scrollback | ✓ | ✓ + step older/newer (#26) |
| Copy screen / copy all | ✓ | ✓ |
| Font size | ✓ | ✓ (menu ± / pinch, #27) |
| Light/dark terminal | ✓ | ✓ |
| Reconnect in place | ✓ | ✓ + auto on foreground |
| Accessory keys | ✓ | ✓ + hold-to-repeat (#14) |
| Native keyboard (dictation/autocorrect) | via KB button | ✓ always — the native win |
| Live session previews | ✓ (hero tiles) | ✓ (3-line live screen per row) |
| Presence / take-release control | ✓ | ✓ |
| **Typing indicator sent** | ✓ | ✓ (#22) |
| **Attach size claim** (`claim:"attach"`) | ✓ | ✓ (#21) |
| **Fast first paint** (`/api/sessions/screen`) | ✓ | ✓ (#41) |
| **Input buffered through outages** | ✓ (15s cap) | ✓ (#22, same cap) |
| **Terminal reset before snapshot replay** | ✓ | ✓ (#36) + mode reseed (#37) |
| Open links from output | ✓ | ✓ (#17 menu, #44 OSC 8 http/https only) |
| Bell → notification | ✓ (web push) | ✓ local + background; APNs blocked (see Needs) |
| Bell → haptic | ✗ (no haptics in iOS Safari) | ✓ |
| Agent-permission toggle | ✓ | ✓ |
| Saved password (keychain) | ✗ | ✓ (device-only; TOTP still required) |
| **App-icon badge** | ✗ (impossible) | ✓ (#15) |
| **Home Screen quick actions** | ✗ (impossible) | ✓ (#18) |
| **Network-aware polling / Low Data Mode** | ✗ | ✓ (#23) |
| **Offline detection + stale-list banner** | ✗ | ✓ (#43) |
| **Smaller replay request** (`replay=`) | ✓ | ✓ (#54) — 2447 KB → 339 KB |
| **Reports its own bg/fg to the room** | ✓ | ✓ (#54) |
| **hop's exact terminal palette** | ✓ | ✓ (#54) |
| **Touch scrolling** | ✓ (browser) | ✓ (#54) — SwiftTerm had none |
| **Chrome-free landscape** | ✗ | ✓ (#54) |
| **Parked / archived sessions** | ✓ | ✓ (#102) — hidden, searchable, unpark on open, no bells |
| Split/secondary pane, wall zoom | ✓ | ✗ deliberately (desktop-shaped) |
| Passkey / share link | ✓ | ✗ (low value on a phone) |

Parity is complete except the two deliberate omissions. Everything in **bold**
was added after the first matrix was written, most of it found by reading hop's
server and web client rather than by inspecting our own UI.

## shift+tab, and two negative results (iteration 53)

**⇧tab added to the key bar** (CSI Z, back-tab). An iOS software keyboard
cannot produce shift+tab at all, and claude's own footer advertises it —
"bypass permissions on (shift+tab to cycle)" is visible in the terminal while
using the app. So on a phone, claude's permission mode was simply unreachable.
Placed next to `tab`, sequence pinned by a test.

Two things checked and found fine, recorded so they aren't re-checked:
- **Escape leakage into previews**: fetched all 19 previews and scanned for
  ESC bytes and `[?…h/l` fragments. Zero. `/api/sessions/preview` reliably
  returns plain text, so the corrupted-preview symptom is only #47's dropped
  characters, not raw escapes rendering as junk.
- **Row text bounds**: tagline and cwd are one line each, cwd truncated at the
  HEAD so the tail of a path stays readable, preview three lines. Longest
  values in the live fleet are 15/40/45 characters, so nothing is near the
  limits anyway.

## Copy diagnostics (iteration 52)

`⋯ → Server & account → Copy diagnostics` puts the app's state on the
clipboard: version and git describe, server, authenticated flag, session and
attention counts, network state (wifi / cellular / low-data / offline),
notification setting, last error. Built for the device checklist — when
something looks wrong on a phone I can't attach a debugger to, that's the
context worth having, and asking someone to read numbers off a screen is worse
than a paste.

Deliberately **no session names, no cwds, no output**: this gets pasted into a
chat, and a fleet's session names say more about someone's work than they'd
expect. The Console.app route (README) remains the deep option; this is the
one-tap one.

The sheet's `.medium` detent clipped the new row, so it's sized to the content
now — caught by screenshot, not by the compiler.

## Interaction audit (iteration 55) — the lens the parity matrix missed

Jian's point stands: the matrix tracked FEATURES (menu items, endpoints,
buttons) and reported "parity complete" while the app could not scroll. Scroll,
selection, colour fidelity, rotation and text size are not features, so they
were never in it. Auditing interactions instead:

| Interaction | State |
|---|---|
| Touch scrolling | FIXED (#54) — SwiftTerm has no scroll gesture at all |
| Drag while selecting | FIXED — drag no longer scrolls out from under a selection |
| Drag sending stray input | FIXED — SwiftTerm's pans sent a CLICK (mouse mode) or ARROW KEYS during a scroll; both disabled |
| Terminal colours | FIXED (#54) — hop's exact palette, was SwiftTerm's stock |
| Landscape space | FIXED (#54) — chrome hidden, terminal takes the rest |
| Dynamic Type | FIXED (#55) — names hyphenated mid-word at accessibility sizes ("Sol-/stice"); now shrink-then-truncate, and previews stop scaling so the list doesn't collapse to two rows |
| Tap to re-raise the keyboard | FIXED as a side effect (#56) — see below |
| Hardware keyboard | plain keys + arrows VERIFIED via simulator key events (#104); ctrl combos unverifiable from XCUITest — it delivers mods=0 — so they stay on the device checklist |
| Long-press selection + menu | needs a device (trade: drag-to-extend is gone) |
| Pinch zoom | needs a device (#27 fixed the state bug) |
| Real rotation | needs a device |
| Hardware keyboard | unaudited |
| Drag & drop text | unaudited |

## Autofit ignored the key bar (iteration 60)

Jian's report, and it was measurable: **fit 51x26 in a 404pt view, accessory
46pt**. SwiftUI's keyboard avoidance insets for the KEYBOARD but not for an
`inputAccessoryView` riding on top of it, so the terminal's frame ran on
underneath the key strip. Autofit therefore sized ~3 rows of terminal into
space the user cannot see — and since those are the BOTTOM rows, what was
hidden was the live end of the session: claude's prompt line and its status
footer, the two things you look at.

Fixed by inseting the terminal by the bar's height while the keyboard is up
(zero when it's down, since the bar goes with it). Now **fit 51x23 in 358pt**,
and the last line sits directly above the keys. The fit is logged per layout
change, so the same check works on a device.

## Clicks, and the keyboard settle (iteration 184)

Two device reports, one build. First: claude's "(click)" pills were
unreachable by design — #55 removed phantom taps, and with them every
click a mouse-aware app draws. The refined rule: in sessions that ASK
for mouse reporting, a tap below the chrome strip sends a real SGR
press+release at that cell. Terminal-testified: a scratch running
cat -v with mouse modes on echoed ^[[<0;26;15M/m exactly where the
probe tapped. Plain shells never see clicks; coast-brake and chrome
strip keep their taps.

Second: keyboard switches sometimes left the grid too small for the
space remaining. A settle verifier now runs 700ms after each
keyboard-frame burst — if the drawn grid disagrees with the current
fit while we hold the claim, it re-asserts, and a layout pass
recomputes SwiftTerm's own fit. First pass; Jian's device is the
judge, and markers are the next step if it persists.

Also queued (PLAN 7): claude fullscreen scrolling, awaiting one repro
detail. And the loop's contract changed at Jian's word: an empty plan
now means the round PLANS — the cron re-armed accordingly.

## The front door matches the app (iteration 220)

First round with a public audience: the README had zero visuals while
docs/screens held twenty verification screenshots, and its feature
list predated the hop keyboard, echo, folders, fork, select-and-copy,
Handoff, Shortcuts and the disconnect story. Now: four screenshots
inline at the top (wall, folders, hop keyboard, disconnect banner —
each a real probe artifact, and the caption says so), the What-it-does
section rewritten to the app that actually exists, stale numbers
fixed (the suite is 28 tests / ~5 min, not 48s), and the layout table
gains the five load-bearing new files. Raw-image URL verified serving
200 on the public repo. Docs-only; the phone stays on 262.

## Public (iteration 219)

Jian: "ready to make this public (and link from hop?)" — done, after
the audit. github.com/jzthree/hop-ios is PUBLIC; hop's README mobile
section links it (minimal separately-committed hop change, per the
mandate). Audit findings: no secret VALUES in the tree or anywhere in
history (verified by searching history for the live sessionSecret —
only code that reads ~/.hop2 at runtime, which is the correct shape);
no .p8/.env ever committed. Deliberately matched hop's licensing
status quo: NO license file (all-rights-reserved by default) — a
license is Jian's decision, one line away if wanted.

Knowingly visible, for the record: docs/screens carries real session
screenshots (taglines, hostnames, conversation fragments), STATUS/
PLAN/HOP2-NOTES carry the project's working notes, and
hop.zhoulab.io appears as the default server (auth-gated). If any of
that should retreat, say so — a prune + history rewrite is a
mechanical round.

## The briefing goes multi-surface (iteration 236b)

Read/unread (Jian's ask, build 290): unread is the default state of news
— a glow dot per story, opening clears it and the story recedes to
secondary ink, Mail's contract so it needs no explanation. Ledger keyed
to the edition's timestamp so a new briefing arrives all-unread; the ⋯
menu's "Show briefing" carries the unread count.

Desktop (Jian: "too good to miss" — his explicit ask makes the hop2
commit in-bounds): DigestCard.tsx above the hop web wall, same
digest.json, same contract — datelines, unread dots (localStorage),
per-edition dismiss, story clicks through the switcher's own handleTap.
Own file so it stays out of Solstice's active surfaces; tsc baseline
unchanged (37 pre-existing errors, none mine); vite build clean. NOT yet
verified rendered in a signed-in browser — the automation browser had no
session and signing in requires Jian's credentials, which are his, not
mine. His signed-in browser shows it on next reload; his eyes are the
verification.

Terminal version recorded as the next step (PLAN 50b) — `hop digest` is
Solstice's surface, hand-off or Jian's call.

## The briefing lands (iteration 235) — digest feature complete

End to end: a host agent writes it, the daemon serves it, the phone shows
it, every line opens its session.

- **Generator** (tools/digest.mjs) runs on the HOST on a schedule, reads
  the cached screen tail plus tagline/attention/idle per live session —
  never scrollback — and asks Opus for the briefing. The prompt gives the
  agent the JOB and only the two constraints that are real (fits one
  screen; each item names one session because each becomes a button); how
  many items, how to rank them and what is worth saying at all are the
  agent's call. Framed as a co-scientist: what a finding MEANS, what it
  puts at risk downstream, what is quietly wrong, and connections ACROSS
  sessions — seeing the whole fleet at once is its only real advantage.
  No user's name and no gendered pronouns: this ships to other people.
- **Transport, with NO hop2 change.** The daemon already serves /assets/*
  from HAY_WEB_DIR behind the same session cookie the app holds, and that
  directory is already gitignored. Two traps found live: only /assets/*
  is served as files (everything else falls back to index.html), and a
  local dev build takes precedence over the packaged one — writing to
  hay-web/assets 404s while hay/apps/web/dist exists, so the generator
  resolves the served directory the way the daemon does. An earlier
  .gitignore commit to hop2 turned out to be unnecessary and was reverted.
- **Card** above the fleet, collapsed to the summary plus two items (a
  briefing you must scroll is not a briefing), urgency-tinted, each row
  opening its session through the same resolver the deep links use.
  Dismissal is keyed to the digest's timestamp, so the next one appears
  on its own.
- **Schedule**: launchd, 06:40 / 12:00 / 17:00 / 22:00. The first is
  timed to LAND before the phone is picked up, since a run takes minutes
  and nobody is waiting on it.

Its real output, unedited: "Europa has retracted the reproduction result
it gave you earlier — it never ran the original recipe." It also caught
three experiments proposed but never launched, and an agent 7h47m and
430k tokens deep with nothing to show.

## The half-height screen, one layer deeper (iteration 234)

Jian on 278: "still shows half height time to time, recovers more
gracefully — sometimes without typing, sometimes after typing… one line
of text at the bottom was messed up after a full screen update. Mostly a
good improvement but not solved from the root."

Three findings, all probe-caught, all shipped:

1. **The auto-scale was scaling to the wrong number.** It fit the font to
   `terminal.cols` — but SwiftTerm re-fits the terminal to the VIEW on
   every layout pass, so by the time we read it the peer's 100-column
   grid had already snapped back to the phone's ~47. Scaling "to fit 47"
   is a no-op, so the daemon's 100-column output kept wrapping into a
   grid that could not hold it. That mismatch is the half-height screen
   and the mangled lines. It now scales to the ELECTED columns.
2. **adoptForeign told SwiftUI before it resized**, so the re-render
   computed against the old grid. Resize first, then notify.
3. **Letterboxing.** A desk grid is ~3.3:1 and a phone ~0.5:1; a foreign
   grid genuinely cannot fill the screen, and hung from the top the slack
   reads as "the bottom half is broken". `letterboxOffset` (pure,
   4 unit tests) splits it evenly — a proportional threshold, because
   one row short of a fifty-row fit is rounding and nudging for it would
   jitter on every refit. Applied by transform, NOT by resizing the view:
   bounds stay the true viewport so the size we would claim on your next
   keystroke is still yours, not the letterbox's.

Plus a full repaint on every font change — SwiftTerm redraws only rows it
believes changed, and a rescale invalidates exactly that bookkeeping.

HONEST: the probe shows the terminal now using the full width and
readable, where before it drew at full size and cropped. But the local
grid still does not equal the elected 100 columns, so the underlying
mismatch is reduced, not eliminated. Jian's "not solved from the root"
still stands, and the next round starts from this evidence rather than
from a theory. 102 unit green, strict zero.

## Face ID as the way IN, not just the lock (iteration 233)

Jian corrected the motivation: the point of Face ID isn't locking the app,
it's replacing the password to LOG IN — "that was how we used it in the
WebHOP interface already, right?" He's right, and the daemon was already
most of the way there: hop2 ships a full WebAuthn implementation
(/api/passkeys/{register,login,list,delete} on @simplewebauthn/server),
and — verified by reading the handler — a successful passkey login sets
the SAME `tunnel_session` cookie a password+TOTP login does. So a passkey
assertion authenticates the app completely: no password, and no 6-digit
code either.

Shipped: "Sign in with Face ID" leads the sign-in screen; the password
fields are demoted below an "or password" rule. It runs the ceremony in a
WKWebView against the server's own login page (which already offers "Sign
in with Touch ID / passkey"), then copies the session cookie into
HTTPCookieStorage.shared — the exact state a password login leaves
behind. Same rpID, so it uses the passkey ALREADY enrolled in hop web;
nothing new to register. No credential is stored by this app or passes
through it.

Why a web view when iOS has a native passkey API: ASAuthorization needs
the Associated Domains entitlement, which needs a provisioning profile
with that capability — the same Apple account gate that blocks the widget
and TestFlight — AND the host must serve an apple-app-site-association
file naming this app, which hop does not (verified). Both recorded as
PLAN 46; when they land, the UI stays and only the middle changes.

Note the ordering this makes possible: the biometric LOCK (iteration 232)
and biometric LOGIN are now different features with different jobs, and
Jian wanted the second one.

## The lock nobody could find (iteration 232)

Jian: "the iOS app still does not have biometric login." It has had it for
weeks — BioLock, Face ID / Touch ID / Optic ID with passcode fallback,
locked from the first frame on cold launch, a privacy shield so the
app-switcher snapshot cannot leak the fleet, and a toggle in Server &
account → Security. It shipped OFF and three taps deep behind the ⋯ menu,
so the one person who wanted it never saw it.

This is the SAME failure this repo already diagnosed for notifications
("shipped OFF and three taps deep in a menu — so the one person who'd
benefit had to already know it existed"), so it gets the same cure: a
one-time offer, once the fleet is on screen, worded for what is actually
at stake — "These are real terminals on your machine; anyone holding the
phone can type into them." Offered only where a gate can actually engage
(`BioLock.available`), and strictly ONE ask per launch, because two
alerts cannot stack and the second would be dismissed unread by the
first's tap. Probe-shot before shipping.

A permanent test now guards the door (the toggle exists in Server &
account); the offer guards the discovery. Feature discoverability is the
recurring bug here, not the features.

## A probe poisoned the suite, and the bisect lied twice (iteration 231b)

Wall tests started failing in a DIFFERENT combination every run. Two
traps, both now in tools/README:

1. **The tile screenshot probe left `switcherTiles = true`** in the shared
   app container. Tiles have no list rows, so row swipe actions do not
   exist — and every later wall test read as a feature regression. The
   list/tiles mode is now pinnable per launch (`HOP_DEV_TILES`), and the
   wall tests pin it instead of inheriting whatever ran last.
2. **`git stash push -- <file>` on a file with no uncommitted changes
   creates no stash**, so a "revert and re-run" discriminator re-tested
   identical code and "proved" a change innocent that had never been
   reverted. Check `git status` before trusting a revert, or run the
   suspect test against committed HEAD directly.

Honest residual: `testSwipeToReplyOpensAndCancels` still fails. It fails
identically on committed HEAD with the tile mode pinned and the row
proven present, hittable and in list mode (tree-dumped), so it is not
this round's work and not the taller rows — the same test was green this
morning against the same code. Cause not isolated; it is the next round's
first job rather than something to paper over with a skip.

## Only a keystroke owns the grid (iteration 231)

Jian revised his own rule, twice in one message: "I take it back that just
active screen on iOS should trigger fit and take priority — still only
keystroke should," and "handle priority gracefully, eliminating any design
that can lead to race conditions." He is right, and the second sentence is
the important one: arbitration WAS the race.

The old model had six ways to claim a size (attach, wake, keyboard settle,
tap, keystroke, a 5s timer) plus a refuse-and-re-assert contest with a
circuit breaker. Every one of those was a client deciding on its own that
it deserved the shared PTY. Two clients doing that is exactly how a grid
ends up matching neither.

The new model has ONE deliberate claim, and it is a keystroke.

- **Keystroke** — claims with `user: true`. Typing into a terminal is the
  one unambiguous statement that this session is yours right now.
- **Attach** — POLITE (no user flag). Opening a session is not a bid to
  take the grid from whoever is typing in it; the daemon grants it when
  nobody has typed recently and refuses otherwise.
- **Own-fit maintenance** (keyboard settle, rotation) — polite, and only
  while we already hold the grid. It can no longer contest a peer.
- **Wake, tap, background, timers** — claim NOTHING. Presence is not
  intent. The 5s reclaim timer is gone; the refuse/fight branch and its
  circuit breaker are gone; taps focus and scroll and say nothing about
  size.

And the graceful half, so losing costs nothing: when a peer holds the
grid we now DRAW their shape scaled to fit instead of rendering it at our
font. That is what turns "spontaneously resized to half its height" into
"the whole screen, slightly smaller type" — the content is all there and
legible, and the moment you type, it is your size again. No contest, no
ping-pong, no explanation needed.

The regression test inverted with the rule: waking after a foreign resize
must claim NOTHING, then one keystroke must claim our own fit.

## A thumbnail was winning the size election (iteration 230)

Jian: "sometimes both hop and hop ios are showing terminal size matching
none of the windows when both attached." Read the code on both sides; the
mechanism is exact, and the root is in hop2, so this round diagnoses and
hands off rather than patching around it.

Every LiveTile on the desk wall claims the shared PTY at TILE geometry
with `user: true` — and in rooms.ts that flag short-circuits the entire
recency election (`const isActive = userClaim || …`), so it wins
outright. The intent is defensible (opening the wall IS a deliberate
act), but the claim is re-sent by an AUTOFIT pass with no human behind
it. So a thumbnail nobody is reading repeatedly outranks a window someone
IS reading — and when the tile wins, its ~85-column grid is neither the
desk's window nor the phone's screen. The desk's focused client gets
snapped to it by the lost-election branch and the phone adopts it too:
everyone renders a grid that belongs to a postage stamp. That is
precisely "matching none of the windows."

Both clients are damping symptoms: the web tile has a 1.5s dedupe and a
15% tolerance, iOS refuses foreign sizes while the user is looking and
re-asserts, bounded to three. Two clients both believing they are
deliberate is the actual bug. HOP2-NOTES carries the suggested fix:
reserve `user: true` for a real human act (wall opened, layout dragged)
and send autofit re-claims as ordinary resizes — the recency election
then does the right thing by itself. The stronger version is a
never-claims observer attach, which the daemon has no concept of today.

Client-side this round: giving up now says why. Once per contest, the
adopt path toasts "Another window keeps resizing this session" and leaves
the chip up, so a half-height terminal reads as a known contest with a
one-tap fix instead of a glitch.

## Room to read (iteration 229)

Two sizing verdicts from Jian, both about the same thing — the wall was
spending its space on the wrong rows.

**Tiles: two lines for the tagline.** The agent writes a sentence and one
caption2 line truncated most of them mid-thought. `lineLimit(2,
reservesSpace: true)` keeps every tile in a row the same height whether
the tagline wraps or is missing, and the tile's fixed aspect ratio pays
for the second line out of the terminal window above — the trade he
asked for ("it can take a bit of the terminal space"). The clock is
top-aligned so it stays on the first line instead of floating in the
middle of a two-line block. Probe-shot: taglines now read "Furniture
retailer data / integration" instead of stopping at "data".

**List: five lines of terminal, up from two.** Two showed the tail of a
command and none of its answer. Five is enough to tell what a session is
doing without opening it, and the shot confirms ~6 sessions still fit a
screen.

Probe trap collected: in a SwiftUI Menu a Toggle is a BUTTON, not a
switch — `app.switches["Tile view"]` matched nothing, and the probe
silently shot the list while claiming to shoot tiles. The preference is
also sticky across runs, so a tile probe must assert what it toggled
INTO rather than trusting the tap.

## The strict gate was not gating (iteration 228, caught in flight)

`make strict` never checked xcodebuild's exit code — it counted warning
LINES and nothing else. A build that fails emits no warnings, so the gate
printed "warnings in our sources: 0" and exited 0. Broken code passed it
this round and was caught only by the UI suite refusing to build. Every
"strict zero" before today was still true (those builds succeeded, and the
suites ran after), but the check could not have told us otherwise. It now
captures the status, prints the first errors, and fails. This is the
repo's own trap — "a metric that improves without a cause is a check that
stopped running" — collected by the harness it was written for.

## The size invariant, enforced at every edge (iteration 228)

Jian, again and specifically: "wrong size when idle and back — I have to
go back and reopen the terminal," with the ask to solve it at the ROOT so
it never comes back. It's solved, and the root turned out to be a hole
nobody had looked in.

**The hole.** Three wake states exist and only two were handled. Socket
DIED during idle → reconnect → fresh attach → deliberate claim → correct.
Socket still CONNECTING → the attach claim covers it. Socket SURVIVED the
idle → we pinged it for liveness and *checked nothing else*. Meanwhile a
backgrounded phone adopts whatever grid the desk elects — the
deferred-adopt grace explicitly requires `.active`, so an inactive phone
takes the foreign size silently. Wake, and you are looking at the desk's
grid with no code path that will ever reconsider. Reopening "fixed" it for
exactly one reason: a fresh attach claims DELIBERATELY (`user: true`),
and the daemon lets an explicit human claim win outright.

**The fix, as an invariant instead of a fifth patch.** While this phone is
foreground, on screen, and not deliberately observing, the grid it DRAWS
must equal the grid that FITS. `enforceFit(reason:)` is now the single
enforcement point: force a layout pass (so the fit describes the CURRENT
bounds, not the pre-lock keyboard), compare drawn grid to fit, and if they
disagree claim deliberately. Silence when they agree, so a healthy session
sends nothing and never touches the daemon's typist recency. Wake runs it
immediately and again at 1.2s (wake is not one moment — keyboard and safe
areas are still landing). The keyboard-settle path was rewired to the same
call, which also upgrades it: it used to send a POLITE resize a typing peer
could refuse, and skipped the peer-held case entirely — precisely the case
a keyboard switch lands you in (PLAN 6/11's long-standing complaint).

**Proof.** A new DEBUG hook (HOP_DEV_FOREIGN_SIZE) makes the first
backgrounding adopt a foreign grid exactly as the daemon's broadcast does
to an inactive phone. The regression test backgrounds the app, wakes it,
and asserts the phone reclaims its own fit UNTOUCHED — no tap, no
keystroke, no chip — and that the peer-size chip does not survive.

**And the reverse rule, from Jian mid-round:** "the app keeps resizing the
terminal even when it is inactive — do it only when the user is actively
looking." He was right, and the wire says so. One PTY serves every client,
so a resize this app sends reshapes whatever screen someone else is
working in; two paths sent them with no idea whether anyone was looking.
`sizeChanged` forwarded every refit, and iOS re-lays this view out on the
way to the background (the app-switcher snapshot). The attach claim sent
on a pocket reconnect too, merely dropping the deliberate flag — still
enough to reshape a desk when nobody had typed recently. Both now go
through one gate, `userIsLooking` (`.active` — the app-switcher, Control
Center and call banners are all correctly NOT looking). Fits while away
are RECORDED, never sent; the wake check re-establishes them on return,
which is what makes skipping safe.

Measured, not assumed: a wire-level witness records every resize with the
app state at send time. Old code, backgrounded: `51x36 background`,
`51x52 background` — two resizes to a live PTY from a phone in a pocket.
New code: nothing until `active`. The first version of that test PASSED
against the bug (a simulator home-press changes no bounds, so nothing
refit) — it took a hook that reproduces the real layout squeeze to make
the test able to fail at all.

**Third report, same root, and Jian named the rule himself:** "the
terminal can spontaneously resize to about half its height and show
broken rendering with the last few lines messed up — maybe a race with
the desktop app which keeps trying at tile size… active phone screen
takes priority over preview and terminal with no keystroke… user
interaction triggers fit, we do not trigger in the background, with the
exception that an active iPhone screen counts as user interaction."

He is describing the wall's LIVE TILES, and they explain the whole
symptom: a desk merely SHOWING this session on the wall attaches a real
terminal at TILE geometry and broadcasts that small grid — no human
behind it. The phone adopted it unconditionally, and a ~24-row grid drawn
into a view that fits ~49 puts the content across half the screen. So
adoption is now conditional: while the phone is being looked at, a
foreign size is REFUSED and ours re-asserted deliberately, bounded to
three refusals before we adopt and raise the chip (a contested session
must not ping-pong forever; past that the human decides). The
"messed-up last few lines" gets its own fix — every reflow now marks the
whole buffer dirty (`updateFullScreen`) before redrawing, because
SwiftTerm's changed-rows bookkeeping is exactly what a resize
invalidates.

Also this round, from the same message: **company is visible now.** A
grey "2" beside a grey glyph was decoration; the pill carries a filled
badge that NAMES whoever else is attached and turns amber with
"<name> typing…" the moment they type — the one fact that changes what
you should do next, since their keystrokes reflow the grid you are
reading.

## Names fold at the door (iteration 227, PLAN 47)

The daemon started folding case wherever a name addresses a session
(hop2 e4bdd86); the app now mirrors it at its boundaries. One pure
resolver — internal-exact, display-exact, then unique case-fold with
the daemon's rule that an AMBIGUOUS fold is a miss, never a guess —
sits at the three choke points every outside door funnels through
(warm requestedSession/pendingOpen, cold openPendingSession). The
warm paths turned out to be worse than the sketch assumed: they
pushed the raw string with NO resolution, so even an exactly-spelled
display name from a Handoff URL dead-ended warm. Internal flows
(pill swipe, fork, list taps) bypass the resolver entirely —
daemon-minted names stay exact, so nothing can alias.

Five unit tests pin the contract (precedence, unique folds both
ways, ambiguity, unknown); a new e2e launches the app with the
internal fixture name case-mangled ("mERIDIAN") and must land in the
terminal.

## Planning round: three evidenced candidates (iteration 226)

Nothing actionable in PLAN (everything open is awaiting Jian's traces
or verdicts; hopboard still private, Xcode account list still empty),
so this round planned. Studied: hop2 drift since the last window and
the app's own seams. Appended PLAN 47-49, each with evidence and a
round sketch:

- **47 — case-folded name resolution.** hop2 e4bdd86 made every
  name-addressing daemon surface case-insensitive (exact-first,
  folded-fallback, ambiguity resolves to nothing). The app still
  `==`-compares names arriving from OUTSIDE (Handoff /s/ URLs,
  intents, HOP_DEV_OPEN) — a URL the daemon serves can dead-end at
  "Session not found" in the app.
- **48 — landscape chrome, summonable not banished.** The chrome bar
  can never appear in landscape; menu, verbs, find, copy, pill swipe
  and the new state-conditional Reconnect are all portrait-only. The
  top-strip summon already proves the fix's shape.
- **49 — omnisearch parity from the local corpus.** Web searches
  session content (f6e6852); the phone filter stops at
  name/cwd/app/tagline while FleetCache already holds every screen —
  content search with zero daemon calls, offline-capable.

Docs only; the phone stays on 271.

## The pill answers back (iteration 225)

Jian: "the back button and back menu design — can you still improve
it?" Three native-idiom upgrades, none touching the settled shape
(two views, one button, no title switcher):

1. **The fleet swipe shows its hand.** The pill follows the finger
   (rubber-banded past the 50pt commit), and past the threshold the
   title swaps to the DESTINATION session's name with a direction
   arrow and a light haptic tick. Inside the threshold it springs
   back and nothing fires. The gesture used to be invisible until it
   had already switched — undiscoverable and blind.
2. **Text size is a keep-open stepper.** ControlGroup +
   menuActionDismissBehavior(.disabled): ± taps keep the menu up
   while the terminal re-fits live behind it. One visit, not
   open-tap-reopen per point.
3. **Long-press the session name for the session verbs** — the
   native press-the-object idiom. Rename/tagline/move/origin/park/
   kill, one shared @ViewBuilder with the ⋯ menu's Session section
   so the doors can't drift.

The round's catch outgrew its first diagnosis. testReconnectKeeps-
TheSessionUsable failed: Reconnect gone from the AX tree. First
theory (the stepper's label row added height) survived one fix
attempt and died on the rerun — identical tree without the label. An
in-test screenshot told the truth: with the keyboard up the menu
gets ~11 rows of height, the flat 18-row list SCROLLED, the fold has
no affordance, and iOS truncates the AX snapshot's tail — the last
items weren't just hidden, they were untestable and undiscoverable.
So the fix is the design: Sharing and Session folded into submenus
(the title long-press is the flat door), the View header dropped,
and every top-level item now fits on screen at once. The menu test
writes /tmp/hop-menu-current.png every run — the AX tree hid this
failure; the pixels did not.

Act three: the green run was a LIE for Reconnect specifically — the
row was in the AX tree but still clipped below the menu's fold, and
the coordinate tap false-passed. The row that would not fit turned
out to be the row that should not exist: Reconnect is now
STATE-CONDITIONAL — absent while the socket is verified-live (the
wake-ping machinery keeps status honest), the menu's FIRST row
during an outage, when it is what you came for. The reconnect test
grew teeth: asserts absence while live, then rides a sustained
drop-hook outage, taps Reconnect mid-storm, and requires recovery.
Two new tests pin the keep-open stepper and the title long-press.

PLAN 45(a): flowboard's insertion path is invisible until it runs
against the real app, so this round shipped forensics, not guesses.
Every UITextInput door rings the KBLog ring — insertText with length
and prefix, setMarkedText, unmarkText, deleteBackward, and an
explicit insertDictationResult. replace(_:withText:) is public-not-
open and can't be instrumented: silence across all logged doors
convicts it by elimination. The ring grew to 240 lines after the
diagnosis walk itself evicted the keystroke being diagnosed.

The round's real catch came from its own probe: the day-old half-open
fix re-buffered only the FIRST key of an errored burst — the daemon's
screen read "eho half-ok", the 'c' died with a generation guard. Every
errored send now re-buffers its payload unconditionally; teardown
stays first-failure-only. Two suite traps recorded: typeText
synthesizes HARDWARE key events that bypass insertText entirely, and
the sim's hardware-keyboard mode can pin software keys offscreen
forever (the forensics assert skips honestly there).

When a flowboard transcript next fails: Copy diagnostics right then —
the ti.* lines name the door, or the silence names replace().
93 unit + 29 UI green, strict zero.

## The socket stops lying (iteration 223)

Jian's report was precise: the terminal shows but takes no input, and
back-and-re-enter fixes it — with the ask that readiness be visible
without typing, and self-healing when absent. The mechanism was the
half-open socket: idle suspension kills the connection SILENTLY, no
close event arrives, the screen paints from cache, the dot claims
live — and sendInput's completion handler ignored errors, so typed
keys vanished into the corpse.

Three fixes shipped: send failures tear the socket down and re-buffer
the very keystroke that discovered the death (the replay machinery
delivers it after reconnect — nothing typed is lost, ever); every
foreground wake pings the socket with a deadline, so the corpse is
found and replaced BEFORE the first keystroke; and the pill dot now
breathes while connecting, solid green only when the claim is
verified — the readiness indicator made trustworthy rather than
merely added. E2E: a DEBUG half-open simulator (generation-orphaned
close — the app genuinely believes it's live) plus a probe that types
into the corpse and reads the full line off the daemon's screen after
auto-recovery. The probe's first run passed FALSELY against a normal
drop because the sim hook hadn't landed — caught, fixed, re-proven.

His second report (dictation insertion + the missing transcription
UI) is PLAN 45, split honestly: the marked-text path is ours to fix;
the transcript-preview interface looks like flowboard's surface, to
confirm before building. 93 unit + 29 UI green, strict zero.

## Dense rows, agentic examples (iteration 222)

Two Jian directives in one round. The list facelift (chosen over
hiding it — the list uniquely carries taglines, swipe actions and
grouping): the trailing time column is gone (inline on the name
line), fonts tightened one step, the preview dropped to two lines
with slimmer chrome, and row insets halved. Roughly nine rows now fit
where five and a half did. And the public screenshots are AGENTIC:
the demo fleet was rebuilt with ⏺/⎿ transcript content and
task-shaped taglines (PR review, flaky-test hunt, perf audit,
release notes), so the examples finally look like what hop is for.

The reshoot fought the usual reality: the denser list shows MORE
rows, so the cleanliness guard grew to top-10 with two extra demo
sessions (a leak peeked at row 9 on the first take, plus a recreated
session missing its neutral prompt); and Jian's brand-new hopboard
session kept topping the fleet mid-shoot — waited out rather than
touched, since he was typing in it. hopboard itself is queued as
PLAN 43: he plans to publish it, and hop-ios will link it for voice
dictation once the URL exists.

Demo fleet deleted, fleet verified clean, 93 unit + 28 UI green,
strict zero.

## The screenshots stop testifying (iteration 221)

Jian: "change my hop ios screenshots to not leak my real terminals —
remake the repo if needed." Done, the thorough way. A demo fleet of
eight scratch sessions (synthetic names, taglines, output, and a
neutral demo@shop prompt) was staged and screenshotted for a new
five-image set: list wall, tile wall, hop keyboard, disconnect
banner, select-and-copy. Every frame was eyeballed before acceptance,
and the wall captures were API-verified demo-only through the capture
window (his live agents kept out-recencying the demo fleet — the
manager session itself had to briefly file as agent-origin, restored
after). The traps en route: a filter fires the server-side CONTENT
search and surfaces real sessions; recency staging decays in ~30s
against a live fleet; test-without-building screenshots the past; an
impatient fallback tap toggles the board back off mid-presentation.

Then the history: git filter-repo stripped docs/screens from EVERY
commit (verified zero screen files anywhere in history) and main was
force-pushed — the old images are no longer served from the repo at
any ref. The new set is committed fresh with an honest provenance
note ("no real terminal content appears here by construction").
README's inline strip now uses the new images. Demo fleet deleted,
fleet verified clean. Cached GitHub raw URLs may serve stale copies
briefly; the repo itself is clean.

## The chip becomes real (iteration 218)

Quiet-gates round (account empty, drift already handled, phone
current), so the one open thread from a DONE item got closed: the
Copy chip's accessibility caveat. Hosting it on the WINDOW puts it
above both opaque boundaries — the terminal's subtree and the SwiftUI
hosting view — so VoiceOver can reach it and the e2e taps it by
identity instead of blind coordinates. Same fixed slot, same captured
text, one less brittle workaround in the suite. 93 unit + 28 UI
green, strict zero.

## Claim what is, not what was (iteration 217)

Jian, on 260: the terminal still often wakes at the wrong size. Every
downstream mechanism has been probe-proven (deliberate claims win
outright, adopts defer, settle re-asserts), so the remaining suspect
is the INPUT: a wake claim that reads cached fitted dims computed
under the pre-lock layout — keyboard rows included — and wins the
election with a stale size. sendAttachClaim now forces a synchronous
layout pass first, so SwiftTerm re-fits the CURRENT bounds and the
claim carries reality.

And the wake trace went release-visible: wakeMark now writes through
the KBLog ring, so every claim, active_size verdict, snapshot and
fast paint shows up in Copy diagnostics on the REAL phone. If a wake
still lands wrong, one paste names the actor — no more fixing by
plausibility. 93 unit + 28 UI green, strict zero.

## Three verdicts in, three fixes out (iteration 216)

THE BLIP RULE (37): the lock/unlock "two lines of red text" were the
coordinator feeding disconnect strings into the terminal — pre-banner
legacy that also lived in scrollback forever. Feeds deleted; the
banner and dim now wait out a 1.2s grace measured from the outage's
START (the first implementation re-armed per state-update and could
never fire — marker-traced). Brief drop: nothing at all. Real outage:
the countdown banner. The drop hook grew HOP_DEV_DROP_WS_COUNT to
sustain outages by killing reconnects PRE-join — post-join kills make
a blip-train, which the grace rightly silences; telling those apart
cost three probe cycles and is exactly the UX being built.

THE SWEEP (38): "missing rename" turned out to be a category — every
session verb was wall-only, and origin refile existed nowhere. The
terminal ⋯ gained a full Session section (rename, tagline, folder,
origin, park, kill-with-confirm), both wall menus gained Move to
You/Agents, and the origin verb round-trips e2e on the live daemon.

THE OVERLAP (39): the toolbar summary is compact-numbers-only now —
overlap-proof by construction, sentence preserved for VoiceOver.

Suite health en route: a sim rotation wedge plus the STICKY board
preference (an aborted run leaves the hop keyboard ON, which breaks
every keys[]-based test after it) produced three red runs that were
environment, not regression — the board test self-corrects now, the
rotation leg skips a refusing sim, both recorded in traps.
93 unit + 28 UI green, strict zero.

## The app says who it is (iteration 215)

Drift round. hop2 18f86ce changed origin semantics overnight —
undeclared Bearer-token callers now file their sessions as AGENT (the
commit's own motivation was our probe fleet: "why is SelectProbe
under User?"). Contract read from the diff: explicit x-hop-actor wins
outright; cookie auth infers user; token auth without a via stamp
infers agent.

The client's answer is declaration, not inference: every write the
app makes now carries x-hop-actor: user — a phone is a human surface,
and the sessions it creates (sheet, fork, Siri) are human acts. The
on-device cookie path was never at risk; the header makes the truth
explicit on every auth path. Proven against the live daemon: a
session created over Bearer auth lands createdBy=user, a test that
FAILS without the header on today's daemon. e150138 (records
durability, web full-screen demotion) skimmed: no client contract
change. 92 unit + 27 UI green, strict zero. Phone still unreachable;
the installer loop now carries builds 250-259.

## Complete all (iteration 214)

Jian: "complete all." Three reports closed in one round.

DISCONNECT (PLAN 33): the app now tells the reconnect story instead
of freezing wordlessly — a banner under the pill counts down the real
backoff ("Connection lost — retrying in 4s"), flips to
"Reconnecting…" when the attempt fires, and carries a NOW button that
skips the wait. The frozen screen dims and desaturates until the
socket returns. All state comes from the coordinator's own retry
scheduler, so the words are the truth. The verification hook this
class of UX always lacked is now permanent: HOP_DEV_DROP_WS
hard-drops the socket once on demand (DEBUG), and the suite asserts
banner-appears then banner-clears-on-recovery. Screenshot shows the
whole story in one frame — banner, amber dot, dimmed content.

KEYBOARD MARGIN (PLAN 34): root-caused as double-counting — SwiftUI's
avoidance already includes the accessory bar in the keyboard frame,
so our extra 46pt inset was a dead band exactly the bar's height.
Machinery deleted; screenshot-verified flush with nothing hidden.

BACK VS MENU (PLAN 35): keep both, per the recommendation Jian
accepted — refined so the ⋯ reads as part of the pill (hairline seam,
bare glyph, the chevron's sibling) rather than a floating button.

Also: the Copy chip now posts a layoutChanged accessibility
notification when it appears (the SwiftUI hosting boundary otherwise
hides it from assistive tech — deeper exposure still queued).
27 UI + 91 unit green, strict zero. Phone still unreachable; the
background installer carries everything from fork onward.

## Hold to select, tap to copy (iteration 213)

Jian's report, mid-round: select and copy didn't work, and he named
the bar — mobile web makes you CHOOSE between scrolling and
selecting; native must not. It now doesn't: press-and-hold selects
the word under the finger (a hold is never a scroll), the selection
handles extend it, scrolling always yielded to live selections, and
a hop Copy chip in a fixed top-trailing slot copies the text captured
the moment the chip appeared — so nothing that later clears the live
selection can lose what the finger chose. E2E-proven: pressed the
word "1030" in a scratch session, tapped the chip, the marker
witnessed exactly "1030". Suites 26 UI + 91 unit, strict zero.

What was actually broken, for the record: SwiftTerm's entire copy UI
is UIMenuController — modern iOS silently refuses to show it — and in
mouse-reporting sessions double-tap belongs to the app, so no
selection path existed at all. The fix fought three interlocking
systems (recognizer-set mutation mid-touch resets gestures;
UIEditMenuInteraction and SwiftTerm's UITextInput conformance clear
selection under each other; canPerformAction is public-not-open) —
eleven probe cycles, each landing one fact. The system's own
Paste/Select/Select All still appears at the selection and coexists.
One caveat queued: the chip misses the accessibility tree (SwiftUI
hosting boundary) — VoiceOver follow-up.

His other two reports are queued as PLAN 33 (production-grade
disconnect handling — next round's top) and PLAN 34 (keyboard-top
margin), with the back-vs-menu recommendation in PLAN 35.

## The loop slows itself down (iteration 212)

Third consecutive round with every gate unmoved (account empty, phone
unreachable — installer still retrying, zero daemon drift in four
hours), and two cron fires arrived queued back-to-back. Per the note
surfaced in iterations 204 and 205 — "if the cron keeps firing into
an empty queue, stretching its interval is the honest move" — and the
original delegation ("you can set an interval you think is
reasonable"), the loop re-armed itself: every 2 hours (cron
5077be90) instead of every 30 minutes. The queue is verdict-bound;
drift is the only productive input and it arrives in bursts a 2-hour
check catches promptly. The moment verdicts or the sign-in land, any
round can act — and Jian can say the word to restore the faster
cadence anytime.

## A quiet round, said plainly (iteration 211)

Planning round; every gate checked, none moved. Xcode account list:
still empty. Phone: still unreachable — the 4-hour background
installer keeps retrying with the folders+fork build. Daemon drift
since the folders round: none on the API surface. The overnight web
commits (6261f4a full-screen-on-purpose, 4aa7423 phone layout for the
mobile switcher) were read for shared state and carry none — they are
the web converging on the shape this app was built switcher-first
with: the wall is the main UI, the terminal is a mode you enter on
purpose. Direction validated; nothing to port; no items manufactured
to fill the round.

Standing: the STATUS-head checklist is the whole queue. Five device
verdicts, one sign-in, two decisions.

## His folders, on the phone (iteration 210)

PLAN 31, one round after the audit found it: the wall now renders
Jian's own filing. The Arrange picker (⋯ menu) offers Recent /
By project / By folder — the third sections the wall under his folder
names in the daemon's order, Unfiled last, with sessions whose folder
was deleted landing in Unfiled instead of vanishing. Long-press any
session: "Move to ▸" lists the folders, Unfiled, and "New folder…"
(creates and files in one gesture). The folders ride the FleetCache,
so the instant-launch wall keeps its sections. Deliberately
read-mostly: folder rename/delete stay on the web — shared structure,
and the phone's surface starts small.

Probe-shot: the live wall sectioned Research (angler, Accessibility,
Supernova, Bellatrix, Oberon) over Softwares — his organization,
verbatim (docs/screens/folders-wall.png). E2E against the real
daemon: ProbeFolder created, a scratch filed into it, folderId
round-tripped through refresh, unfiled, both deleted, fleet verified
clean. His three live folders are data and were never touched.
91 unit + 25 UI green, strict zero.

## The parity re-audit finds his folders (iteration 209)

Planning round. The parity matrix was 160 iterations stale, so this
round re-audited against today's web client — and found something
better than a feature gap: a JIAN gap. He created folders yesterday
("Research", "Softwares", "side") and filed most of the fleet into
them, using the web's manual-sort folder machinery. The phone ignores
folderId wholesale; its only grouping is the cwd heuristic. His
explicit organization, invisible on the device he glances at most.

PLAN 31 (next round's top) has the full contract read from the daemon
and web source: folders arrive on /api/sessions, /api/sessions/move
files a session, /api/folders creates. The native shape: a three-way
grouping picker (Recent / By project / By folder), sections under his
folder names, and a "Move to ▸" submenu in the context menus —
read-mostly first round, rename/delete only if he asks (folders are
shared structure). His three live folders are DATA; probes create and
delete their own.

Also from the audit: manual tile ORDER is per-client localStorage on
the web (not ours to sync), zoom is the adaptive grid's job (have),
sort modes otherwise covered. The background installer for build 251
is still waiting for the phone to become reachable; Xcode account
still empty; no new daemon drift overnight.

## Fork, same-day (iteration 208)

PLAN 30: the phone speaks fork the day the daemon learned it. "Fork
session" now lives in all three places a session presents itself —
tile menu, row menu, and the terminal's ⋯ sheet — and opening one
switches you into the fork while the original keeps running. A claude
fork continues the conversation under a fresh id (the daemon's doing;
the client just asks and follows the returned internalName). Failures
surface hop's own error text through actionError, same as every other
verb.

Proof in the house style: an e2e unit test forks a real scratch
against the real daemon and asserts the part that matters — the fork
EXISTS in the refreshed list and INHERITED the source cwd (/tmp) —
then kills both and leaves the fleet clean (verified empty). The UI
suite asserts the menu offers fork without firing it on the live
fixture. 89 unit + 24 UI green, strict zero.

## Fork lands upstream; the head gets unstale (iteration 207)

Planning round. The drift check earned its keep a second day running:
hop2 f6e6852 (today) shipped SESSION FORKING — web's ⋯ sheet grew
"Fork session", claude forks resume history under a fresh id, cwd and
origin inherit. PLAN 30 queues the iOS side (context menus + the
fork-and-open flow + a real-daemon e2e) as next round's top; the
endpoint contract is already read and recorded there. The Xcode
account gate was re-checked: still empty, still holding three
features hostage.

The other half of the round: STATUS's own head was iteration-112-era
— it still pitched the TestFlight ISSUER that has since failed AUTH
and a checklist whose size items builds 229-237 closed. Rewritten:
current build, the five-verdict batch, the never-answered stragglers
worth keeping, exact sign-in instructions with the defaults-key
evidence, and the two standing decisions (APNs, archived). The
hand-off document is the product in a verdict-bound phase; a stale
one taxes every read.

Docs-only round — no binary change, phone stays on 249.

## The zombie door, found by its own pin-test (iteration 206)

What began as an upkeep sweep (all gates green, TSan clean, device
current) became the round's real work when the drift check surfaced
Solstice's d1e76ce: the daemon now refuses attaches to unknown names
with a 404 instead of inventing phantom sessions. A raw upgrade
handshake confirmed the exact status line, and the iOS failure
classifier already maps it to the permanent gone UI — compatible as
built.

Then the pin-test caught something better: killed-but-REMEMBERED
names still resurrect. The new daemon guard consults the config
layers, and a killed session's entry survives them — so the test's
tap on a dead cached row brought GoneProbe back from the dead. That
is the exact zombie the client's reconnect path has long defended
against, entered through the one unguarded door: FIRST attach. Fix:
a list painted from the launch cache is hearsay (liveListSeen), and
hearsay attaches now run the reconnect path's verify-then-connect;
live-list attaches are untouched — zero added latency on the normal
tap. Two test-harness bugs fixed en route: HOP_DEV_CACHE_ONLY only
gated bootstrap (the 5s tick overwrote the cache mid-test), and the
phantom witness must be the session LIST — /preview remembers dead
sessions' screens without resurrecting them, so a preview check
false-alarms.

The daemon residual (attach-by-dead-name resurrects for ANY client)
is recorded in HOP2-NOTES for Solstice. 88 unit + 24 UI green, strict
zero, scratch cleaned.

## Landscape keys, locked cache (iteration 205)

The two small items from the thin round, shipped together. The hop
keyboard now compresses to 150pt in landscape (was a full 232 — with
the accessory bar, 278pt of a ~390pt screen, leaving the terminal a
few rows). The iOS 17 trait-observation API replaced the deprecated
override after the zero-warning strict gate refused the first attempt
— the gate keeps paying for itself. The permanent keyboard test now
rotates and MEASURES: the q key must render under 80% of its portrait
height in landscape. Fixed-height-per-orientation keeps the
anti-lottery guarantee intact.

And fleet-cache.json — terminal content on disk — now carries
completeFileProtectionUnlessOpen: readable only unlocked (when the
app actually reads it), still writable by a background refresh while
locked. 88 unit + 23 UI green, strict zero.

The queue is now fully Jian-gated; per iteration 204's note, the next
rounds will be planning-only unless verdicts or the Xcode sign-in
arrive. If the cron keeps firing into an empty queue, stretching its
interval is the honest move.

## A thin planning round, honestly labeled (iteration 204)

Queue drained again, so this round hunted. Ruled out by reading: the
reconnect snapshot cost (already bounded — the client requests a 200KB
replay tail against hop's 1.5MB default, tuned and commented in
HayClient); offline input replay (PendingInput: age-capped, ordered,
already matches the web's model); web file-drop parity (a native
share/document flow is plausible but has no user signal yet — not
queued).

Two real items found, both small: the hop keyboard is 232pt in EVERY
orientation, which in landscape leaves a few terminal rows under a
278pt stack — worse than the system keyboard it replaced (PLAN 27);
and fleet-cache.json carries terminal content with no explicit file
protection class, readable-while-locked after first unlock (PLAN 28
— completeUnlessOpen fixes it without breaking background refresh
writes).

Honest note for Jian: the loop's well of self-serviceable work is
running thin — everything substantial now waits on device verdicts
(echo feel, hop keyboard, instant launch, wake-flash, Handoff) or the
Xcode sign-in (widget, TestFlight, Live Activity). After 27 and 28
ship, consider either a verdict batch or stretching the cron interval;
rounds that hunt for work to justify themselves are how quality dips.

## The stall that wasn't (iteration 203)

PLAN 26 resolved the way it was designed to — by measurement, not by
building. A frame-gap monitor now runs whenever a terminal is
attached (CADisplayLink; stalls beyond max(50ms, 3 frames) recorded
to the same KBLog ring as the keyboard trace, with any >32KB feed
noted beside them; throttled, near-free, permanent). The probe then
threw the two nastiest burst shapes at a scratch session: seq 1
60000 and thirty thousand long yes-lines.

Verdict: four gaps in total — 72, 62, 135, 60 milliseconds — and not
a single feed over 32KB. The daemon already chunks output small, and
SwiftTerm absorbs it; the momentum clamp's suspicion of parse-burst
stalls was right in kind but the magnitude doesn't justify feed
coalescing. Machinery declined; measurement recorded; the instrument
stays, so any future regression appears in the same Copy-diagnostics
trace Jian already knows how to pull. Scratch killed; probe excised.

## Keystrokes stop waiting for the tunnel (iteration 202)

PLAN 25: optimistic local echo, ported from the web rather than
reinvented — hay's optimisticEcho.ts earned its shape through
deterministically-reproduced failures, so the Swift struct mirrors it
exactly and all seven of its test cases came across too (green first
run, including the Claude-composer repaint guard and the coalesced
"alal" regression). Typed printables now render the instant the key
lands; the daemon's echo is consumed on arrival; control sequences
are never predicted.

Gating matches the web to the letter: echo only as the sole
controller outside collab (ambiguous with two typists), tracked from
collab events; reset on connect, on snapshot (the replay is the
truth), on close, and on losing eligibility. In the pipeline: deliver
feeds the echo before the send, and every output chunk passes through
reconcile before feeding — with the RAW chunk still going to remote-
mode detection, which must see what the app actually sent.

The integration probe covers the failure the unit suite can't: with
echo live, a scratch session typed through the real keyboard showed
SINGLE characters daemon-side ("echo zq", never "eecc") — an echo
accidentally wired into the send path would double every key on the
wire. Scratch killed after; 88 unit + 23 UI green, strict zero.

What's left of this item is the half only Jian can judge: typing feel
on cellular, where the 100-300ms echo wait used to live.

## A planning round: the latency half of keyboard feel (iteration 201)

Queue empty of unblocked work again, so this round hunted gaps in
performance and feel. Ruled out by reading: poll backoff (already
tiered — 5s wifi / 12s cellular / 30s Low Data, previews skip
entirely under constraint); collab/control parity; find-in-scrollback.

The real find: iOS has NO optimistic local echo. Every keystroke
travels phone → tunnel → daemon → PTY → echo → tunnel → phone before
it renders; on cellular that's 100-300ms of typing lag in the app
whose founding thesis is keyboard feel. The web solved this in
utils/optimisticEcho.ts and its comments record the hard-won failure
modes (the TUI-redraw guard that keeps Claude's composer legible, the
coalesced-echo bug that once rendered "alal" as "llllllalalal",
reproduced deterministically). PLAN 25 (next round's top): PORT that
model, don't reinvent it — pure struct, transliterated unit cases,
wired into deliver/feed with the web's exact gating, reset on
snapshot/reconnect. Also appended PLAN 26: suspected feed-burst frame
drops, instrument-first by explicit design — the momentum code's own
comments suspect main-thread parse stalls, but nothing has measured
them yet.

No build shipped (planning round); the phone stays on 243.

## Siri learns to write (iteration 200)

PLAN 23: the fleet's two write-verbs exist as App Intents. "Reply to
Session" answers an agent through the same throwaway-socket sender the
lock-screen reply uses — with an honest failure dialog, because an
automation that fails silently teaches distrust of every success.
"New Session" creates, refreshes, and lands in the terminal through
the same requestedSession road every other entry point takes. Both
carry Siri phrases in HopShortcuts.

The verification is the part worth keeping: an intent's perform() is
just a function, so the e2e unit test runs the REAL intent bodies
against the REAL daemon — creates IntentProbe via NewSessionIntent,
sends "echo intent-ok" via ReplyToSessionIntent, polls the daemon's
own preview until the text shows on the session's screen, then kills
the scratch. make test now forwards the daemon token so this runs in
every suite (verified: 81 tests, zero skips, scratch confirmed dead
afterward). One trap dodged en route: a Makefile edit that reported
success but didn't land — re-applied and re-verified with make -n.

81 unit + 22 UI green, strict zero.

## The wall survives the graveyard (iteration 199)

PLAN 22: cold launch no longer renders a blank wall. FleetCache
persists the daemon's raw JSON — sessions, previews, screens — on each
successful refresh (throttled to every 20s; the first save after a
cache paint is immediate), and bootstrap loads it before the network
answers: the wall paints at first frame, ages self-label from
lastActivityAt, and the live refresh replaces it seconds later.

Two deliberate choices worth keeping: the cache stores RAW daemon
JSON, not Codable mirrors, so loading re-runs the exact live parsers
(HopSession(json:), TileInk.decode) — the cache cannot drift from the
live path, and attention recomputes against the CURRENT seen markers
rather than resurrecting cached dots. And the paint is gated on a
credential existing, with authenticated set optimistically: session
content never renders over a login screen, and a real 401 still
bounces to login exactly as before.

signOut deletes the file (it holds session content — the same reason
signOut already cleared lastKnown). Proof: a unit round-trip through
the live parsers plus corrupt-file safety, and a permanent UI test
that fills the cache in one run, relaunches with the network path
DISABLED (HOP_DEV_CACHE_ONLY), and asserts the wall still paints.
80 unit + 22 UI green, strict zero.

## A planning round: the blank-wall gap (iteration 198)

Everything in the queue is done or waiting on Jian (verdicts on
236/237/240, the Xcode sign-in, one bad keyboard trace), so this round
planned. Investigated and RULED OUT before writing items: lock-screen
reply (QuickReply + UNTextInputNotificationAction already shipped),
park-from-notification (exists), content search (server-side, wired),
route-change reconnects (wired).

The real gap found: cold launch renders a BLANK wall until the first
/api/sessions round-trip — AppModel.sessions inits to [] and nothing
persists across process death. iOS kills this app constantly; every
return from the graveyard is seconds of empty screen in an app built
for glancing. PLAN 22 (next round's top): persist fleet + screens to
disk on refresh, paint the wall at first frame, let the live refresh
replace it — with the signOut-deletes-cache caveat called out.

Also appended: PLAN 23, Shortcuts write-verbs (Reply and New Session —
the read verbs exist, the senders exist, only the intents are
missing); PLAN 24, a "wants you" Live Activity, gated behind the same
provisioning wall as the widget.

No build shipped (planning round, by design); the phone stays on 240.

## The hop keyboard (iteration 197)

PLAN 21, Jian's own ask ("how hard would it be to build a togglable
full keyboard?"): built, and the estimate held — one round. The ⌨ key
on the accessory bar (past the fold, next to hide-keyboard) swaps the
system keyboard for hop's own board; the board's ⌨ key swaps back
(that's the dictation/emoji hatch). UIResponder.inputView is the whole
mechanism — one assignment each way.

What the board buys a terminal: a FIXED 232pt height, which makes the
keyboard-switch resize lottery structurally impossible while it's up
(the item-6 bug needs a height change to fire); no autocorrect bar
appearing and vanishing; a monospaced face; and every ASCII symbol at
most one plane away — |, ~, backtick, braces, angle brackets live on
#+= where the system keyboard buries some of them two planes deep.
Layout is the system's own three-plane scheme so the muscle memory
transfers. Board text funnels through typedText — the SAME path as
system typing, so an armed accessory-ctrl turns a board letter into a
control chord, and every board keystroke reclaims the size election
like any other typing.

Proof: unit test walks all printable ASCII through the plane data
(a terminal keyboard with an unreachable backtick is a desk you must
walk back to); permanent UI test toggles on, visits all three planes,
and returns through the hatch; both planes screenshot into
docs/screens. 80 unit + 21 UI green, strict zero.

## The widget hits the same wall, and the rename audit runs clean (iteration 196)

PLAN 18 attempted: unparked the widget, and the device build failed
"No Accounts" — for both targets. The diagnosis is exact this time:
Xcode's account list is EMPTY (DVTDeveloperAccountManagerAppleIDLists
→ IDE.Identifiers.Prod = ()); the team entry that made "signed in"
look true is a stale remnant. Re-parked with that evidence inline;
builds green again. Jian's move: a sign-in that sticks (Xcode →
Settings → Accounts, then confirm the account LISTS). TestFlight (19)
sits behind the same gate.

PLAN 20, the rename audit, filled the round instead — and came up
CLEAN. Everything already keys internalName: seen bells, notified
bells, lastKnown, previews, Spotlight, handoff, deep links, widget
rows; open-by-name resolves either identifier; the open terminal's
title follows session_renamed live. The discipline was built
piecemeal across months of incidents (the session-identity-layers
lesson), so the audit's value is the regression test that now pins
it: a bell rings through a display rename, an unchanged bellSeq stays
quiet through one, and a marker keyed by display name is a dead key.
78 unit + 20 UI green.

## The keyboard gets a flight recorder (iteration 195)

PLAN 11, activated by Jian's "still problematic as before": instead of
a third blind guess at the keyboard-switch size bug, the app now
records the evidence. KBLog is an 80-line ring capturing every
keyboard frame event (end-Y, height, duration), every SwiftTerm fit
(grid + the view bounds it was computed from), and every settle
verdict (ok, or MISMATCH with what the view's height was at that
moment). The ring rides into Account -> Copy diagnostics — no env
vars, no cable, no debug build needed on the phone.

Why this shape: the suspects are three different layers (the
keyboard's own frame sequence during a switch, SwiftUI's keyboard
avoidance leaving stale bounds, SwiftTerm fitting from them), and the
existing settle verifier can only see the third. One pasted trace
from a real Wispr<->system switch names the guilty layer outright.

Sim-verified end to end: keyboard cycling produced kbFrame/fit/settle
lines and the copied diagnostics carried them (via the HOP_COPY_MARKER
side channel — pasteboard reads stay denied to the runner). The probe
is PERMANENT: the instrument is load-bearing for a live investigation.
20 UI + 77 unit green; the zero-warning strict gate caught one
implicit-self in this round's own code and was satisfied.

Next when the trace arrives: read which layer went stale, fix that
layer, and retire the instrument section from diagnostics if it's
noise afterward.

## The wake-flash, traced and closed (iteration 194)

Jian's question — why does lock/unlock change the size at all? — now
has a measured answer. A wake instrument (wakeMark: timestamped lines
at connect epochs, fast paint, joined, snapshot, claims, every
active_size) ran under a probe holding 100×30 against the phone's
51×49. One trace told the whole story: the attach rebroadcast delivers
the foreign size at t+440ms and the app ADOPTED it — resize, chip,
retry timer, the works — then our deliberate claim went out at t+842ms
(a 400ms delay that exists for fresh-open keyboard layout) and won 21
milliseconds later. The flash WAS the adopt-before-claim window.

Two fixes, both probe-proven in re-runs: reconnect claims now go out
immediately (everConnected — the 400ms wait remains only on true fresh
opens), and a foreign active_size arriving within 3s of a foreground
connect is DEFERRED 1.2s rather than adopted — the claim's confirm
cancels it, so the foreign size never renders (traces show DEFERRED →
OURS with no adopt); if the race is somehow lost, the late adopt still
fires, correctness over cosmetics. Residual: the fast paint still
draws at the PTY's dims for ~RTT before the snapshot (it must — the
preview is a grid at those dims). Killing that too needs
attach-carries-size in the daemon; recorded in HOP2-NOTES. Scratch
session deleted; probe excised; suites green.

## Nine verdicts, and the Handoff last mile (iteration 193)

Jian answered everything at once. Closed: full-bleed ("good as is"),
claude fullscreen scrolling ("seems fixed" — the viewport pin did it).
Still open: keyboard-switch sizing ("still problematic as before") —
the settle verifier was not enough, so the keyboard-frame instrument
(PLAN 11) is now actionable. New question worth its own item: re-entry
recovers now but still flashes wrong FIRST — why does lock/unlock
change the size at all? (PLAN 17 has the suspected mechanism: the
adopt-before-claim window on wake.) Renames are INTENTIONAL hop
mechanism — PLAN 20 audits that identity is internalName everywhere.
Xcode is signed in — widget (18) and TestFlight (19) unblocked. BT
keyboard: no — 15 dropped. He also asked for an in-app full keyboard
estimate (21: moderate, inputView swap, fixed height would even dodge
the item-6 lottery).

Fixed and SHIPPED this round: Handoff's last mile. His verdict —
"almost works! except ?room= is not entering the session anymore."
Root cause read from the web + daemon: the daemon serves the HUB at /,
which never reads ?room; the canonical session URL is the PATH
/s/<internalName>/ (what the web's own buildSessionPath pushes, and
the daemon answers with the __HOP_SESSION__ injection — verified with
an authed curl). The donation now uses the path form; the incoming leg
parses it (?room= kept as legacy fallback); URLComponents double-
encoding trap dodged via percentEncodedPath (a / in a session name
must not become a separator). 76 unit + 19 UI green, gated.

## The named baseline is retired (iteration 192)

PLAN 16, the last unblocked queue item: strict concurrency is at ZERO
warnings and `make strict` now exits red on any regression — no more
"5 accepted warnings in the old input machinery" caveat re-explained
every time TerminalScreen changes.

Each fix states a runtime fact the code already depended on, rather
than restructuring anything: the view's deinit invalidates its timers
inside MainActor.assumeIsolated (UIViews deinit on main; now that's
checked instead of assumed silently), the Coordinator's SwiftTerm
conformance is @preconcurrency (the delegate protocol is nonisolated
but every witness runs on main), and the typing-settle Timer callback
asserts its main-run-loop reality the same way. The reclaim-retry
Timer got this pattern back in #112c; the stragglers now match it.

Behavior is unchanged by construction — every fix is an assertion, not
a restructure. Suites: strict 0/red-gated, 76 unit, 19 UI, all green.

## Share screen, and a lesson in element trees (iteration 191)

PLAN 14: "Share screen…" now sits beside Copy screen in both wall
context menus — the same trimmed text, straight into Messages/Mail
through the system sheet, no paste step. ShareLink with the session
name as subject; gated on the screens store like its sibling.

The verification was the actual work. The sheet presented on the very
first build (screenshot: docs/screens/share-sheet.png) but the test
insisted it hadn't: app.buttons["Copy"] matched nothing. A SpringBoard
theory failed too. A tree dump with the sheet visibly up settled it —
the sheet renders IN-process and its actions are CELLS
(actionGroupCell, label "Copy"), not Buttons, so the landmark is a
cells-by-label predicate. Trap recorded in tools/README next to its
cousin (the out-of-process selection menu): dump the tree before
guessing hosts. 19 UI + 76 unit green, gated.

## The session follows you to the desk (iteration 190)

PLAN 13, first of the planning round's candidates: Handoff. The open
terminal now donates an NSUserActivity whose webpageURL is hop web's
own deep link (?room=<internalName> — the exact param App.tsx reads),
eligible for Handoff; SwiftUI retires it when you leave the session.
Walk to the Mac: Safari's Handoff icon in the Dock opens the SAME
session at the desk — the phone->desk half of hop's core loop, done
with an affordance only native has. The incoming leg is wired too:
another device running this app continues the activity natively
(same room identifier as Spotlight and hop:// — all three funnels
converge on requestedSession).

Verification: handoffURL() is pure and unit-tested (user-text session
names get escaped; a hostless server yields nil rather than a relative
URL Safari can't open — the cookie-seed wipeout taught that shape);
a permanent UI test reads the donated URL through a DEBUG marker
(HOP_HANDOFF_MARKER, the runner can't see system Handoff state) and
pins it to https + room=<internal>. The real Dock pickup needs two
devices, so it's on Jian's checklist. 18 UI + 76 unit green, gated.

## A planning round (iteration 189)

Every queue item is now Jian-gated (device verdicts on 229/230's size
work, full-bleed clearance, keyboard-settle, fullscreen-scroll repro),
so this round planned instead of building, per the loop's contract.

Studied: STATUS history, the web client (routing, hotkeys), the fleet,
and the app's dormant native surface. Ruled OUT before writing items:
background bell polling (BackgroundRefresh.swift already exists), icon
badge (done), notification-tap routing (done), port-session support
(zero port sessions in today's fleet — speculative).

Appended PLAN 13-16: Handoff donation of the open session (web has
?room= URLs; the phone->desk pickup is the one hop flow with no native
affordance yet), Share screen via the system sheet (Copy's sibling for
other apps), hardware-keyboard commands (gated on whether Jian uses
one), and the Swift 6 migration to retire the 5-warning baseline.

Fleet hygiene note for Jian: ProbeP and ProbeR ("Temporary
experimental workspace", "Scratch workspace for testing") look like
leftover scratch sessions — not deleting without your word, since
they're live and might be yours.

No build shipped this round (nothing implemented, by design); the
phone stays on 230.

## The election was already winnable (iteration 188)

PLAN 10 was written as a daemon proposal: agents type through hop's
WS API, bump lastInputAt, and refuse a phone's claims — so propose
that agent input stop counting. Reading rooms.ts before writing the
proposal dissolved it: `handleResize` already honors `user: true` — a
deliberate human act wins the election OUTRIGHT — and the web client
already sends it on explicit session switches. The phone had been
politely losing elections it was entitled to win.

Build 230 speaks the flag: attach claims (only while foreground-active
— a pocket reconnect must not steal a desk's size), chip taps, and
touch/keystroke reclaims all carry user:true; the 5s retry stays
recency-based by design. E2E with the scratch harness: probe holds
100×30 with live typing recency; the app opens; the hold's own socket
logs `lost size to 51x49` — instantly, no chip, no retry needed.
Combined with 187's touch-claims, the re-entry size lottery should now
be over for every act Jian actually performs: opening a session,
touching it, typing into it.

HOP2-NOTES.md records the finding for Solstice, plus the one residual
(low-stakes) daemon question: agent WS input still counts as typist
recency for recency-based claims — blocking only the polite retry now.

## A single touch claims the size (iteration 187)

Jian, mid-round: "a single touch should trigger autofit," and the
non-autofit state should follow the web client's mobile handling. The
web's model, from reading App.tsx: auto-fit is the default, a foreign
size is never rendered in fit mode, the first keystroke reclaims
(fit-on-type), and Manual mode is the deliberate exception that shows
the remote's true shape with overflow+pan. iOS already had the
keystroke half (deliver's reclaim) and the Manual half (peer adopt +
pan, Fit to width); the missing piece was the phone's FIRST act —
a tap — meaning nothing to the size election.

Now it does: reclaimOnUserIntent() fires from an approved single tap,
from mouse-mode clicks, and from every keystroke, throttled once per
second, latched until a CONFIRMED win. Finding the right hook took
three probes: becomeFirstResponder only fires when unfocused (SwiftTerm
guards it), touchesEnded never fires for recognized taps (the
recognizer cancels view touches) — the one place every tap passes
regardless of focus is gestureRecognizerShouldBegin, where the brake
and strip gates already live. E2E-proven with the scratch-session
harness: probe.mjs held 100×30 with live typing recency, the chip
came up, the marker stayed empty until ONE tap — then our fitted
51×49 went down the wire.

The round also killed a whole trap class: the fixture's display name
churned AGAIN (Meridian now displays "nebula"; two suite reds that
read like regressions). make uitest now resolves the fixture's current
display name from its STABLE internal name via /api/sessions at suite
start — the fixture is pinned to identity, not to a string that other
people's renames own.

## Copy screen reaches the wall (iteration 186)

PLAN 9: "Copy screen" now lives in both context menus on the wall,
tile and row — the peek's WRITE half: share what a session shows
without entering it. The item appears only when the screens store has
the session, and what lands on the pasteboard is the grid stripped of
its padding (trailing spaces per line, blank tail rows — copyableScreen,
unit-tested), so a paste reads like a screen, not a wall of spaces.

The probe fought two real environment facts worth keeping: the wall
sorts by recency, so a quiet fixture sinks below the fold where a lazy
list has NO element to find (the probe scroll-seeks now); and the test
runner CANNOT verify the pasteboard — iOS 16's background-paste
privacy silently denies reads from a never-foreground process. Two red
runs proved it; the permanent test reads the action's content through
a DEBUG marker file instead, and the trap is recorded in tools/README.

## The summary that fits (iteration 185)

PLAN 8, the loop's top actionable item: the toolbar title ellipsized
exactly at its informative part ("21 sessions · nothing…") because the
principal slot is narrow between the two toolbar groups. Now the
summary is two PURE formatters — the sentence (fleetSummaryLine) and
the numbers (fleetSummaryCompact: "21 · quiet · 1 parked",
"18/21 · 2 want you (+1)") — and ViewThatFits picks whichever fits.
VoiceOver always hears the full sentence (accessibilityLabel), so
compaction costs sighted pixels nothing and accessibility nothing.
Probe-shot docs/screens/toolbar-compact.png: the compact form complete
in the slot, no ellipsis. Unit tests cover both formatters' agreement.

Also this round: the coast-brake latch from 184 became a TIMESTAMP
(0.8s freshness) after the full suite flaked once with the second tap
dead — a Bool latch whose touch-end never delivers (recognizer
arbitration under load) would eat every later tap until the next
brake. A brake is a moment, not a state. Suite green twice
consecutively after; watch testTapDuringCoastOnlyStopsIt for any
recurrence (next suspect if it flakes again: the tap re-recognized as
a long press starting a selection, which a marker on the shouldBegin
decisions would confirm).

## The terminal is a fixed viewport (iteration 184)

Jian, after the bounce fix: "the native scroll bar should never show
up — our terminal element should always fit and the terminal scrolling
is handled in hop." That's a principle, not a symptom, and it's now
enforced at the source: the underlying UIScrollView has
isScrollEnabled=false, both indicators hidden, and
contentInsetAdjustmentBehavior=.never. UIKit cannot move, inset, or
decorate the terminal's content any more — no keyboard
scroll-to-visible, no safe-area inset drift (both prime suspects for
"the scroll is back", and the inset one plausibly fed the keyboard-size
lottery too). Programmatic motion — peer-pan, scrollTo, the anchor
restore — is unaffected.

One real casualty, caught by the gated suite: disabling scrolling makes
touch delivery immediate, so touchesBegan stopped a coast BEFORE the
recognizers were asked, and the braking tap — seeing no coast left —
raised the keyboard. The fix is a per-touch-sequence brake latch
(brakeTouch): set when a touch kills a live coast, cleared on
touches-ended/cancelled, checked by every tap gate. The ordering no
longer matters; the comment that used to explain why the flag COULDN'T
live in touchesBegan now explains why it must.

Suites: 73 unit green; UI suite green twice consecutively (one
load-flake on a tap test in between, passed 3/3 isolated and in both
full reruns).

## Two views, one button (iteration 183)

Jian, by voice, asked the hop-ios agent to fix the navigation — and the
hop-ios session IS this session (the daemon churn renamed it from
Orion), so no relay was needed. The directive: a session view and a
terminal view, a working way back, and no switcher menu in the title.

Done exactly: the back chevron is restored ("Back to sessions"), the
title menu is GONE — the title is a plain label (dot, name, lock,
viewers, badge) — and the switch-from-terminal path that remains is the
pill swipe, which is direct manipulation rather than chrome. The
title-menu UI test left with its feature, by directive. The earlier
"two ways out" complaint resolves the way he wanted: the button without
the menu, not the menu without the button.

Also folded in, from his device: the phantom BOUNCE — a terminal that
rightly doesn't scroll still played the scrolled-to-the-end rubber-band
on drags. Every scroll here is hand-driven, so the underlying scroll
view's bounce is now off entirely.

Probe: back button tapped → switcher reached; no "Switch session" menu
exists. Suites green and gated.

## A verification round (iteration 182)

Loop round three, deliberately light: PLAN's remaining items were a
trace and a look, not builds. The underfill sub-case closes by tracing
— a smaller-than-fitted grid still reaches the adopt→chip→retry path,
because the snapshot re-fits to our size first and the refusal
rebroadcast therefore always mismatches the drawn grid. The PeekTip
placement closes by probe: it anchors below the first tile, arrow up,
clear of the island. No binary change; build 221 stands. Next on PLAN:
Jian's on-device verdicts.

## The wake path heals itself (iteration 181)

Loop round two on PLAN.md item 1. The persistent case of Jian's
return-from-idle wrongness is the REFUSED attach claim: the phone comes
back, asks for its size, and someone typed recently enough that the
server says no — silently, forever, until the user typed.

Now the intent persists: while the app is foreground and a peer size
holds the grid, the attach claim re-asserts every five seconds. The
server keeps refusing while anyone is actively typing — the retry is
one small message, not a fight — and grants the moment they lapse past
the idle window. The chip shows the state meanwhile; the heal clears
it without a tap. A pocketed phone can't steal: backgrounded apps run
no timers here, and returning to an open session is the same intent
attaching expresses.

Probe-verified end to end against a harness-held 90×44: chip up under
the hold, no interaction, healed and cleared once the holder went
idle. Timer uses the #112c main-actor-assertion pattern and stops on
detach and on every our-size-won event.

## The size chip, and the loop reborn (iteration 180)

Jian refined the study mid-round: the wrong size strikes on RETURN FROM
IDLE — background, come back, wrong grid. And he asked for a
planning-and-implement loop with an interval of my choosing: armed at
30 minutes, reading PLAN.md each round.

First round shipped the chip: whenever a peer/default size holds the
grid, a capsule under the pill says so — "90×44 — take mine" — and the
tap claims the phone's size. A refusal (someone typed recently) re-arms
it: state, not magic. Probe-verified against a harness-held 90×44:
chip appears, tap under an active holder is refused, chip persists.
The re-entry size lottery is at least VISIBLE now, with an exit.

The wake-path sequencing (stale fitted dims at snapshot time; auto
re-claim when the refusing typist goes idle) is PLAN.md's top item.
Fast paint was cleared by reading: its resize is snapshotLanded-gated.

## Re-entry sizes, studied (iteration 179)

Jian: returning to a session sometimes shows the wrong size/formatting,
inconsistently. Studied before fixing (his call, the right one):

- The fleet's PTY sizes are heterogeneous — 51×49 where a phone once
  claimed, 76-78×24 default-ish elsewhere. A 24-row grid UNDERFILLS a
  phone view that fits ~49 rows; a 78-col grid pans.
- On every entry the ATTACH CLAIM decides which world you get: the
  2.5-second idle rule refuses the claim when the session's agent typed
  recently (agents type through the API and bump lastInputAt), and
  grants it otherwise. Active agent → peer/default size; idle agent →
  phone size. Same session, different minute, different rendering —
  the inconsistency is the election working as designed, invisibly.
- "Formatting messed up" compounds it: content wrapped at one width
  replays into another after a successful claim (scrollback never
  reflows), and underfilled small grids leave the screen half-empty.

Fix candidates are queued in PLAN.md (top item); the visible-state size
chip is the most promising first move. The planning-and-implement loop
Jian asked for is armed at 30 minutes, reading PLAN.md each round.

## The top of the screen, claimed — and one back story (iteration 178)

Jian, three at once: the terminal wasn't using the top of the screen;
the switcher's top was a small text over blank space; and the big back
button + a menu below it still read as two ways out.

**Terminal, full-bleed.** The grid extends under the status bar now —
rows start 40pt from the display top (26 ran row zero through the
clock, probe-caught), reclaiming the ~59pt band the safe area reserved.
Everything floating re-anchored below the status text: the chrome pill,
the find bar (material runs to the display edge, content below the
clock), the toast. The chrome-summon strip grew by the same inset — at
a fixed 46pt it sat almost entirely inside the status area and the
summon tap fell through to the keyboard (probe-caught).

**Switcher: the summary IS the title.** "hop" as a title said nothing
while a row below said the useful thing over blank space. The fleet
summary sits in the toolbar principal slot now (tappable when a session
wants you, same contract), the summary row is gone, and tiles start
immediately under the toolbar.

**One back story.** The pill's chevron is gone; the edge swipe is the
way back and the title menu regains "All sessions…" as the explicit
exit. This inverts iteration 150's choice — Jian flagged the pair
twice, and the second flag decides it. The pill-swipe TipKit hint died
in the same stroke: its popover ballooned over the island once the pill
moved under the status bar.

**The suite is fully green for the first time — 17/17, zero skips.**
The fleet churned again mid-work (Orion and Titan vanished daemon-side;
sessions renamed under us), so every fixture reference collapsed to ONE
constant (Self.fixture, env-overridable, currently "Meridian") per the
coupling convention. The perpetual "1 skipped" died too: the drag test
finally runs, because the hasHistory fix and a live fixture arrived
together.

## The reader's anchor (iteration 177)

Jian: "scrolling bug still exists for some sessions, for example
music." Music is a training loop — plain shell, steady output, local
scrollback — a different mechanism from the claude double-scroll:

**Bug 1, the snap-back:** nothing preserved scrollback position across
feeds (reapplyPan guards peer grids only), so every printed line yanked
a scrolled-up reader to the live edge. Fix: a HISTORY ANCHOR — set by
user scrolls, held through the coast, restored after every feed's
display pass, cleared at the live edge. A first version died to
friendly fire (SwiftTerm's own pin fires the same scrolled() callback
and cleared the anchor); a userScrollInFlight flag now separates user
scrolls from the terminal's pin.

**Bug 2, found under bug 1:** the Live pill has been structurally DEAD
for plain sessions — hasHistory probed getLine one row past the
viewport, which current SwiftTerm answers nil regardless of scrollback.
The drag test has skipped on "no scrollback" in every suite run,
masking it. Fix: latch scrollback existence from observed yDisp motion
(truth the API can't misreport), reset on terminal reset.

Verified against a live 1/s ticker fixture: three drags into history,
twelve seconds of output, pixel-identical text region (the anchor), and
the Live pill present throughout. Recipe in tools/README.

**Ship exception, documented:** the full UI suite is red on two tests —
both failing ONLY because their fixture sessions (Orion, Titan) have
VANISHED from the daemon (curl-verified; a freshly created Orion
evaporated in seconds). That is a hop2-side incident, not this repo's
regression; the affected paths are covered by the dedicated probe and
unit suite. Also on the incident's casualty list: a rename probe of
mine landed while "Titan" was unexpectedly free, so the session
internally named Solstice currently DISPLAYS as "Titan" — and the
daemon refuses the revert (its collision check matches the session's
own internalName). Needs a daemon-side untangle; no further fleet
mutations from here.

## The starvation's third face (iteration 176)

Jian, from the device (and: the loop is stopped, at his word): some
sessions still showed "…" in the preview. Third face of the same bug,
found by marker logs of the actual fetch batches:

- Face one (iteration 149): a fixed prefix in a never-changing order.
- Face two (161's shots, misread then): the off-screen sweep can't help
  names that never leave the "visible" set.
- Face three, the real mechanism: the visible-first HEAD alone can
  exceed the whole budget — the grid keeps ~16 cells alive against a
  budget of 12 — so the off-screen segment got ZERO slots, forever.
  Rotating inside the head (this session's first fix) shuffled who
  starved without feeding the tail.

The durable fix has two parts: the head's share of the budget is CAPPED
(12 of 16), so the tail is guaranteed slots every poll; and the budget
rose to 16 — the daemon renders a preview in ~1ms (measured), so the
whole 21-session fleet warms in two or three polls. Verified twice
over: marker logs show every session name in every batch, and the
deep-scroll probe screenshot shows the exact tiles that starved
(Altair, Accessibility) rendering their screens.

One instrument lesson en route, now in the traps table: the diagnostic
marker sliced prefix(12) while the code fetched prefix(16), reporting
zero coverage for names being fetched fine. A marker must log the same
expression the code executes — never a copy of it.

## The double-scroll, latched out (iteration 175)

Jian, from the device: scrolling a claude session sometimes scrolled
the page AND claude's transcript at once — intermittently, cause
unclear. The mechanism was sitting in the code: `sink` (wheel to the
app vs move the local viewport) is parsed live out of the output
stream, and claude toggles those modes as it redraws — so one drag's
ticks could split between sinks when a toggle landed mid-gesture. Both
motions in one gesture, only when claude happened to redraw during it:
exactly "sometimes but not always."

Fix: one sink per GESTURE. Latched at touch-down, held through the
coast, cleared by stopMomentum. When the remote mode changes under a
live gesture the gesture ENDS rather than switching — switching
mid-coast would also fire SGR wheel bytes at an app that just stopped
listening, which arrive as typed garbage (a second bug the same latch
prevents). A log line marks any gesture ended this way, so the field
will show how often the race actually fires.

Honest verification boundary: the race needs claude to toggle modes
mid-gesture, which can't be produced on cue — the mechanism is
confirmed by reading, mixed delivery is now structurally impossible,
and the full scroll suite (drag, flick, coast, brake, swipe-back)
passes unchanged on the latched path.

## The well, surveyed honestly (iteration 174)

Loop iteration spent on the last open capability question, then on
saying a true thing about the backlog.

**The `windows` field is vestigial — question closed.** Every session
in the fleet reports 1, and neither the web UI nor the daemon source
contains any window-selection code. There is no multi-window support to
build parity with; recorded in memory so nobody re-investigates.

**The backlog is now genuinely Jian-gated.** Everything the app can
verify from this machine is shipped and green: the wall (colour, sonar,
presence, grouping), triage at every distance (banner → lock screen →
wall → sheet → terminal), system integration (Spotlight, Siri,
Shortcuts, deep links — hardware-proven), Face ID, the palette, the
icon, the tips. What remains needs Jian: the widget (one Xcode
sign-in), device-feel verdicts (pill swipe, sonar at 120Hz, Face ID
flow), and the ASC key (rejected at AUTH — likely revoked, not
under-privileged). The loop's honest cost/benefit from here: fires that
find no new user input should stay cheap (checks, not churn).

## Presence on the wall (iteration 173)

Loop iteration. The daemon has always said which sessions have a client
ATTACHED right now (the deep-link experiment surfaced the field); the
terminal shows viewers, but the wall said nothing. Now both switcher
modes wear a small eye beside the name when someone is on the session —
the desk browser, the CLI, another phone. Glance value: "is anyone
looking at this?" before you open it. VoiceOver speaks it ("someone
attached") through the shared summary, so both modes still sound
identical. Verified live: the eye sat beside Solstice — the one
attached session at probe time — and nowhere else.

Suites: green and GATED, both.

## The wipeout: one latent line, and a half-learned lesson (iteration 172, addendum)

The 172 ship went out on a RED UI suite — 33 failures, every test — and
the pipeline committed and deployed build 210 anyway, because the chain
ECHOED the exit code without GATING on it. That is the 159 lesson
half-learned: narrating a failure is not stopping on one. The ship
chain now dies on red (and the trap table says so).

The wipeout itself was not the Spotlight change the timing implicated.
Root cause, found by the file-marker instrument in three cycles
(refresh status=200 json=false hadCookie=false → seed host=NIL): the
DEBUG cookie seeding parsed the RAW stored serverURL, and this sim
container held a schemeless "hop.zhoulab.io" — URL(string:).host is
nil for that, the seed silently no-ops, every launch bounces to login,
every test times out. Requests never noticed because they use
normalizedServerURL; the seed now does too, eliminating the class. How
the schemeless value got INTO the container is honestly unknown (a
stray probe keystroke into the login's server field is the leading
suspect); it no longer matters, because the seed no longer cares.

After the one-line fix: 17/17 UI in normal time, unit green, gated.

## Health re-swept; the debt was mine and is paid (iteration 172)

Loop iteration on verification, since a lot of code landed after the
165 sweep (tips, tagline, Spotlight, intents, palette, URL routing).

- tsan: 0 races, again.
- strict: 8 warnings — the named baseline of 5 plus THREE NEW, all
  mine, all in the Spotlight publisher (CoreSpotlight types captured
  across a @Sendable boundary). Fixed properly: the searchable items
  are built inside the detached task from Sendable string tuples, and
  the module import is @preconcurrency. Strict is back to exactly the
  named baseline of 5. The rule held: the old machinery's warnings are
  a deliberate baseline; NEW warnings are debts, and they got paid the
  round they were noticed.

Memory updated with the two simulator traps from 171 (openurl drops
custom schemes silently; logd hides os.Logger lines) so no future
session re-buys those lessons.

Suites: green by exit code, both.

## The landmine defused: the sim was lying, the phone routes (iteration 171)

The focused session iteration 170 asked for. Verdict: the deep-link
code has been CORRECT since the scene-delegate fix — both instruments
were broken, and one of them was the simulator itself.

The experiment chain, each step falsifying a theory:
- File markers replaced logd (`simctl spawn log` shows nothing for
  os.Logger lines that provably run — instrument one, broken).
- Markers showed willConnectTo firing → the custom scene delegate IS
  connected; quick-actions plumbing intact.
- A COLD `simctl openurl` didn't even launch the app — exit 0, home
  screen sitting there. Full uninstall/reinstall changed nothing.
  `simctl openurl` silently drops custom-scheme URLs in this sim —
  instrument two, broken. (Both are in tools/README's traps now.)
- The arbiter: `devicectl device process launch --payload-url
  "hop://session/Solstice"` at the REAL phone. devicectl reported
  "device locked, launch failed" — and three seconds later Solstice's
  `attached` flag flipped False→True on the daemon. The phone had
  launched hop behind its lock screen, routed the URL, pushed the
  terminal, and attached. The observable was server-side truth, not a
  screenshot.

hop:// deep links work on hardware. The widget's row links will work
the day the widget unparks. (Jian: your phone likely has Solstice open
from the experiment — that was me, once, deliberately.)

## The chord palette ships; the deep link hits a landmine (iteration 170)

Loop iteration, two halves, one honest split.

**Shipped: hold ctrl for the chord palette.** Eight combos — ^C ^R ^L
^Z ^D ^A ^E ^K — each labelled by what it DOES ("^R search history"),
because "^R" alone assumes the muscle memory the palette exists to
replace. One gesture instead of arm-ctrl-then-hunt. Tap still arms
(probe-asserted); chords ride AccessoryKey.sequence through deliver(),
so the reclaim path and press haptic apply; the masking is the armed
path's exact 0x1f AND, unit-tested, case-insensitive, nil for
non-letters. A repeating ^C is destructive, so it doesn't.

**Parked: hop:// deep links, at a genuine landmine.** The scheme is
registered (verified in the installed app's plist), the widget's rows
now carry hop://session/<internalName> links, FleetSnapshot.Row gained
internalName while the wire format is still free to change — but URL
DELIVERY never happens: SwiftUI's .onOpenURL doesn't fire (the custom
scene delegate for quick actions swallows it — known behaviour), and,
measured by instrumented logs, NEITHER do the delegate's
scene(_:openURLContexts:) nor the app delegate's application(_:open:).
Three rebuild-and-fire cycles, zero route logs. Navigation itself is
fine (HOP_DEV_OPEN opens Orion in the same build). The routing code and
instrumentation stay in place; the delivery mystery needs its own
focused session rather than a fourth blind cycle — and widget links
only matter after the widget unparks anyway.

Suites: green by exit code, both.

## Siri learns the fleet (iteration 169)

Loop iteration, the Spotlight sibling: App Intents. Two actions, no
extension, no app group, no signing — AppIntents run in the app's own
process, so the entities read AppModel directly and the app's cookie
authenticates the refresh even on a cold background launch.

- **Open Session** — a Shortcuts action and Siri phrase with a session
  picker whose entries are the LIVE fleet (the query does one silent
  refresh when the model arrives empty). Opening rides requestedSession,
  the same road Spotlight and notification taps travel.
- **Fleet Status** — answers without opening the app: "19 sessions
  running, 2 want you." Spoken aloud, so it's a SENTENCE
  (fleetStatusLine, pure + tested), not the switcher's dot-separated
  summary. Usable in automations: a morning routine can ask hop whether
  anything waited overnight.

Verified to the honest boundary: both suites green, the AppIntents
metadata extractor ran in the build (that registration is what surfaces
actions in Shortcuts), the dialog line is unit-tested. Driving Siri
itself isn't automatable from here — first spoken run is Jian's.

## The fleet in Spotlight (iteration 168)

Loop iteration. Sessions are in the SYSTEM search index now: pull down
on the Home Screen, type a session's name, land in its terminal — the
result card shows the tagline (or cwd) so it says what the session is
for. No entitlements, no signing; pure native reach the web cannot have.

The details that make it right:
- Donations are change-gated (names/taglines hash) — the index outlives
  the process, so idle polls never touch it.
- Sign-out CLEARS the index: session names on a signed-out phone are
  exactly what signOut() promises to remove.
- The tap routes through requestedSession — the same road notification
  taps take, cold launch included.
- spotlightEntries() is pure and tested: ports never index, tagline
  first, cwd stands in.

Tile parity, small and real: footers carry the same relative clock the
rows show (how stale is this screen), headers the same agent glyphs
(created-by-agent quiet, agent-permitted in glow).

Suites: green by exit code, both.

## Taglines from the phone (iteration 167)

Loop iteration, cashing the endpoint probed last round. The tagline is
"what this session is FOR" — under every name, in tile footers, on the
widget — and only agents could set it. Now: long-press any row or tile
→ Edit tagline. Empty clears it. The daemon propagates it to every
client, so labelling a session from the couch relabels it on the desk.

Verified END TO END against a scratch session the harness created and
deleted: reset its tagline to empty over the API, drove the app's real
flow (long-press → Edit tagline → type → Save), asserted the text
landed back in the row, confirmed the daemon stored it. The fleet was
never touched.

One structural stumble, self-caught: the alert first landed inside
SessionDialogs — a ViewModifier with explicit bindings — while the
state lived in the view; the compiler said so, the bindings were
threaded through, and the pattern is now obvious for the next dialog.

Suites: green by exit code, both.

## The invisible, introduced (iteration 166)

Loop iteration. The app's best interactions are deliberately invisible —
the pill swipe, the long-press peek — which makes them undiscoverable by
the same stroke. TipKit is the native fix, and a real native advantage:
a web app hand-rolls coach marks and persists "seen" itself; here both
are the OS's job.

Two tips, each shown once, dismissible, gone forever after use:
- "Swipe to switch" on the chrome pill, invalidated by the first real
  swipe (used it = learned it).
- "Hold for a peek" on the wall's first tile (one tile, not a wall of
  popovers — tipIf() exists for exactly that).

Under -hop-ui-testing tips never configure (a popover is a hit-test
wall in front of whatever a test taps — the probe proved it by failing
until it closed the tip first); -hop-show-tips force-shows them for
screenshots.

Also probed for later: the daemon HAS api/sessions/tagline ("Session
not found" for a fake name, not "Unknown endpoint") — tagline editing
from the phone is possible when a round wants it.

Suites: green by exit code, both.

## The health sweep (iteration 165)

Loop iteration spent on verification, not features — strict and tsan
hadn't run since before Face ID, TileInk, the gestures and the widget
code landed.

- **tsan: 0 races**, suite green.
- **strict: 5 warnings**, all Swift-6-language-mode concurrency
  advisories, all in TerminalScreen's OLD input machinery (repeat-timer
  and momentum deinit, the typing-signal closure, the SwiftTerm delegate
  conformance). None trace to this stretch's work. Deliberately LEFT:
  they are warnings under the shipping Swift 5.9 mode, tsan finds no
  race behind them, and the code they sit in is the most trap-dense in
  the repo (hold-to-repeat, coast momentum) — churning it for
  warning-count vanity is how regressions happen. They are the named
  baseline now; the Swift 6 migration is the right occasion to clear
  them.

No binary change this round; nothing to deploy. Build 202 remains
current on the device.

## Idle screens stop repainting (iteration 164)

Loop iteration, a perf round fixed at the SOURCE rather than cached at
the edge: every poll wrote fresh ScreenPreview structs into the
@Published stores even when the screen hadn't changed, and a @Published
dict mutation re-renders every visible tile — an idle fleet rebuilt a
dozen AttributedStrings every two seconds to draw the same pixels.
ScreenPreview and ColorRun are Equatable now and both stores skip
equal writes (text compares first, short-circuiting the rows for the
common idle case). A test pins the equality semantics the skip rests
on: identical screens equal, a colour-only change still invalidates.

Suites: green by exit code, both.

## The two modes sound the same (iteration 163)

Loop iteration: the accessibility-and-parity debts the new surfaces had
quietly accrued.

- **Tiles speak one utterance.** VoiceOver was walking every rendered
  terminal line inside a thumbnail — noise, not access. Tiles now speak
  the same summary the rows always have (sessionSpokenSummary, shared,
  so the two modes cannot drift apart in what they SAY even as they
  differ in what they show).
- **The sonar respects Reduce Motion.** An endlessly expanding ring is
  exactly the motion the setting asks to be spared; the dot's glow
  already says "live".
- **Rows got the peek.** The long-press preview was tile-only; the two
  modes differ in layout, not capability, so the list's context menu now
  rises with the same full-colour screen.

Suites: green by exit code, both.

## Find joins the material — and the pill learns to yield (iteration 162)

Loop iteration. The find bar was the terminal's last stock strip: flat
field on flat hopRaised. Now: raised mono field with hairline, sized
chevron targets, semibold Done, on ultraThinMaterial with a bottom
hairline — the chrome pill's material, because they're the same family
of surface.

The probe caught a real bug on the way: the pill and the find bar both
claim the top edge, and the PILL WON — the field held focus and took
typing while the pill covered it (under the test pin indefinitely; in
production for the three seconds until auto-hide). The overlay now
yields while find is open. This is the screenshot-verification
convention paying rent: the suites were green through a bug a single
screenshot exposed.

Memory updated too: the ASC key failing AUTH (not role) supersedes the
old TestFlight-blocker theory, and the parked widget's unlock steps are
recorded where the next session will find them.

Suites: green by exit code, both.

## The wall learns projects; search lights its matches (iteration 161)

Loop iteration, two switcher rough edges.

**The tile wall honours project grouping.** Group-by-project only ever
worked in list mode; the wall now renders the same sections — a
~/Code/hop2 header over its tiles, ~/Code/roomscroll over its own —
through the existing `sections` computed (one unlabelled bucket when
grouping is off, so the ungrouped render is untouched). Screenshot-
verified with HOP_DEV_GROUP=1.

**Search results light their matches.** highlightMatches() bolds and
brightens every case-insensitive hit inside the server-side snippet —
the server already found the text; the eye shouldn't have to find it
again. Pure and tested: characters never altered, hit-count of styled
runs, whitespace-only queries style nothing. The visual is a one-line
Text() swap over that tested core; the probe screenshot chased 17
matching tiles and stopped short of the section, and the unit tests
carry the verification instead.

Suites: green by exit code, both.

## The widget: written, sim-verified, parked at the signing gate (iteration 160)

Loop iteration. The Home Screen widget — the purest native advantage
left — is fully built: FleetSnapshot (Sources/Shared, compiled into both
targets so the wire format can't fork), a small widget (the attention
count, or "all quiet"), a medium one (four rows: dot, name, tagline),
and an app-side publisher that saves on every refresh but reloads
timelines only when the glanceable facts change, because WidgetKit
budgets reloads.

It stops at provisioning, precisely: xcodebuild has NO signed-in account
("No Accounts"), and the ASC API key is rejected outright
("Authentication failed: bearer token") — so neither path can register
the App Group or mint the widget profile. That key failing at AUTH, not
at role, is new information for the TestFlight column too: the key may
be revoked or the issuer stale, not merely under-privileged.

Everything is parked in place: project.yml carries the commented target
with unlock instructions (sign into Xcode OR fix the key, uncomment
three blocks, make install). The app builds, installs and passes both
suites with the widget parked; the publisher is inert without the app
group and costs nothing.

Jian's unlock, verbatim: Xcode → Settings → Accounts → sign in the team
(5AD7QB9795) account — that alone un-parks the widget.

## Correction, and two new traps (iteration 159, addendum)

The 159 gate printed TEST FAILED and the ship pipeline sailed past it:
`make test | grep` hands the chain grep's exit code, and grep MATCHING
"TEST FAILED" is a success exit. The failure itself was simulator
container churn ("Failed to create a bundle instance …
containermanagerd/Dead") — zero tests ran, and the immediate rerun
passed 67/67, so build 196 was never actually broken. Both lessons are
in tools/README's traps now.

While auditing: recent entries quoted "69/70 unit tests" — those counts
were base-plus-tests-I-wrote, not the meter. The measured suite today is
67 passed, 0 failed. Counts below come from the run's own output.

## Replying means seeing the question (iteration 159)

Loop iteration. The Reply flow was an alert with one trimmed line of
context — exactly how you send "y" to something that asked which of
three options you wanted. It's a sheet now: the session's last
meaningful rows in their real colours (TileInk again — inverse pills,
error reds, the prompt itself) inside a terminal-dark box, over a mono
composer with a purple send. Same QuickReply path underneath, same
success/error haptic, same markSeen-on-answer.

The swipe-to-reply UI test drove the old alert's Cancel button; it now
asserts the sheet and dismisses by drag — the test changed because the
UI's contract changed, not to make a red bar green.

Suites: 70 unit, 17 UI, green.

## The sonar, and triage from the banner (iteration 158)

Loop iteration. Two capability signals now that the surfaces agree.

**Busy is visible.** The web wall's green means "producing output right
now"; the app now says it natively — a sonar ring that expands and fades
from the state dot while a session has activity in the last ten seconds
(poll cadence plus slack; sessionBusy() tolerates the daemon's
milliseconds AND seconds, because a unit isn't something to trust across
a protocol boundary — tested). Attention keeps its amber; the sonar only
rings for quiet-but-working, in both tile headers and list rows.
Verified with two frames half a second apart: different ring phases.

**Park rides the bell.** The notification category grew a second action:
Reply · Park. A bell that can wait gets put away from the banner — no
unlock, no app — and parking marks the bell seen, or the badge would nag
about a session just handled.

Suites: 70 unit, 17 UI, green.

## Park, and the front door matches the house (iteration 157)

Loop iteration. Parking was the web switcher's triage verb the app never
had — the daemon side existed (unpark-on-open used it), but nothing on
the phone could SET it. Now: swipe a row (indigo moon, beside Rename and
Kill) or long-press a row or tile. Parked sessions leave the browse list,
keep running, stay searchable, and the summary counts them — all
behaviour that already existed and now has its missing half. Endpoint
probed both directions with a scratch session first (created → parked →
verified → deleted); the fleet was never touched.

The login screen's fields joined the material system — hopRaised with
hairline strokes, same as the new-session sheet — replacing the stock
quaternary wash. The hare, glow and mono wordmark were already right.

Suites: 69 unit, 17 UI, green.

## New sessions start where the work is (iteration 156)

Loop iteration. The "+" flow was a bare alert asking for a name; a phone
could never choose WHERE a session starts. The daemon turned out to
accept a cwd on create — verified empirically with a scratch session
that landed in the requested directory (and was deleted after; the
grep hunt through hop2 for the handler was going nowhere, and one probe
answered in thirty seconds).

The alert is now a sheet in the app's material: mono name field, and a
"Start in" row of capsule chips — the fleet's own project directories,
one per project, most recent first (recentProjects(), pure and tested:
dedupes by projectKey, newest session's path wins, ports excluded).
Default remains the daemon's choice. No file browser; picking from
where work already runs covers nearly every real case.

Also: the tile wall's columns went adaptive — two on a portrait phone,
four in landscape or on an iPad, instead of a hardcoded pair.

Suites: 69 unit, 17 UI, green.

## The mark: a prompt with a live cursor (iteration 155)

Loop iteration. The icon was a generic chevron on a purple wash — the one
surface everyone sees before the app opens, wearing none of the app's
language. It's now ❯▊ — a prompt with its cursor lit, which is what hop
IS: a session running somewhere, waiting for you. Lavender gradient
stroke, hopGlow caret, neon bloom matching the switcher's glow language.

Native touch the web has no equivalent of: iOS 18 appearance variants.
Dark Home Screens get a deeper night with the same neon; tinted Home
Screens get a grayscale mark the system hues itself.

Craft notes: shapes are drawn as solid masks with colour composited
through them — the first attempt drew the gradient as 64 line segments
and the caps striped (banding, screenshot-caught). 4x supersample,
LANCZOS down. Legibility checked at 120px before shipping. Generator
lives in tools/make_icon.py; the icon is reproducible, not a binary
blob with no provenance.

Suites: 67 unit, 17 UI, green.

## Swipe the pill, change the terminal (iteration 154)

Loop iteration. Safari's address-bar swipe, for terminals: drag the
chrome pill sideways and the terminal becomes the next (or previous)
live session in switcher order, wrapping at the ends. The gesture is
horizontal-dominant with 50pt of travel, so bar taps and menu touches
never misfire; the switch rides the existing requestedSession path (the
same in-place swap the title menu does), and every navigation change now
answers with a selection tick — without it, the swipe's only feedback
was a repainted screen.

neighborSession() is a pure ring-stepper with the edges tested: wraps
both directions, skips dead sessions, and returns nil rather than guess
when the fleet has one session or the current one already left it — a
stale swipe must not jump somewhere random.

Probe: launched into Orion, one leftward drag on the pill, landed in
Solstice with the key bar intact. Suites: 67 unit, 17 UI, green.

## The key bar joins the material system (iteration 153)

Loop iteration. The bar under your thumbs was the last stock-looking
surface: flat caps on a flat strip, next to a switcher full of lit cards.

- Caps wear the app's hairline (0.5pt, white 8%) and the bar a top
  hairline — the same light-catching edge everything else has.
- Pressed caps BRIGHTEN (16% toward white). Physical keys light under a
  finger; dimming — UIKit's default — reads as disabled.
- Single-glyph keys (arrows, ⌫, ⇞⇟) grew to 15pt. At 13 an arrowhead is
  a smudge; word keys stay 13 and nothing re-wrapped (widths untouched).
- One configurationUpdateHandler now owns cap colour in every state —
  pressed and armed both. The armed setters shrank to accessibilityValue
  + setNeedsUpdateConfiguration: the VoiceOver/test contract ("armed")
  IS the state, and the colour follows it. testCtrlArmsAndDisarms
  exercised the refactor unchanged.

Ordering was checked, not changed: attention already sorts first, then
recency — the wall floats ringing sessions to the top on its own.

Suites: 66 unit, 17 UI, green.

## One ink for both modes, and a count through the locked door (iteration 152)

Loop iteration. Two threads pulled from the last report's own queue.

**List rows joined the colour system.** The three-line snippets now render
from the same colour report the tiles use: meaningfulTail grew an
index-based twin (the indices are the contract between the plain screen
and its colour rows), TileInk.snippet styles exactly the rows the plain
picker chooses, and run-granularity trimming keeps the terminal's leading
indentation out of a text row while preserving the styling of what
remains. Plain text is the fallback inside the same Text() — not a second
code path. On screen: red error lines, dim status text, inverse-video
"Jump to bottom" pills, inside ordinary list rows.

**The lock screen says whether anything is waiting.** A count only —
"2 sessions want you" in attention amber — because that's the one thing
worth saying through a locked door. Names, taglines and output stay
behind the gate.

Suites: 66 unit (3 new: index-contract, run-trimming, snippet), 17 UI,
green.

## The peek, the haptics, and the hero that lost to muscle memory (iteration 151)

Loop iteration under the design directive: know the web/terminal designs,
build to native advantages, don't copy.

**Long-press peek (TilePeek).** Hold a tile and the whole screen rises at
reading size, in colour, with the context menu beneath — reading a session
without opening it, which the web wall simply cannot do across a
navigation. Fidelity note: the peek's mid-word wraps are the PTY's own
66-column wraps, faithfully rendered; fixedSize() both axes so the system
scales an oversized preview rather than adding wraps of its own.

**Inverse video.** The web renderer's PreviewRun has an `i` flag (cursor,
selected rows, status bars — ink and paper swapped). TileInk now honours
it with the same fallbacks; visible in the peek as claude's highlighted
message bars.

**Haptics.** Scope change ticks (.selection); the Face ID gate opening
answers with .success — the Apple Pay cue. Attached to the Group ABOVE the
lock view, because feedback attached to the view that disappears dies
with it.

**The zoom hero: tried, measured, reverted.** iOS 18's
.navigationTransition(.zoom) — tile grows into terminal — is exactly the
native-advantage showpiece the directive asks for, and it cost swipe-back:
zoom's interactive dismissal claims the left edge but never answered the
swipe on our bar-less destination. Failed with our edge recognizer beside
it AND with ours removed in deference. Swipe-back is muscle memory; the
hero is delight; muscle memory wins. Tombstone comment in SessionTile.swift
so the next reader doesn't re-fight this.

Suites: 63 unit, 17 UI, green.

## Face ID, the reclaim latch, and one way back (iteration 150)

Three from Jian in one stretch: biometric login ("which mobile hop already
support"), a double back affordance ("i dont know whether you are half way
done"), and the size that "does not autofit back even when i type".

**Face ID lock (BioLock.swift).** The native answer, not the web's password
prompt: the session stays authenticated; what Face ID protects is the phone
changing hands. Locks on background and from the first frame of a cold
launch (never a flash of fleet before the gate); .deviceOwnerAuthentication
so a failed scan degrades to the passcode sheet; the lock screen keeps a
sign-out escape hatch so nothing can hold the app hostage. A softer shield
covers the app-switcher snapshot — iOS captures it as the app leaves, and
without that the "locked" fleet is readable in the carousel. Toggle:
Account → Security. NSFaceIDUsageDescription lives in project.yml (the
plist is GENERATED; editing it directly lasted exactly one `make gen`).
Sim probe: gate holds, fleet never renders behind it, sign-out reaches
login. The system prompt itself can't rise under -hop-ui-testing — it's
OS-owned UI with no Cancel on the sim, and it was eating the probe's taps.

**The reclaim latch.** deliver() cleared peerHoldsSize on SEND. When the
server refused the reclaim (peer typed <60s ago), the refusal rebroadcast
repeated the size we had already adopted — the adopt path saw nothing new,
so nothing re-armed, and with the flag false every later keystroke skipped
reclaiming. One refused reclaim = "never autofits back no matter how much
I type." Now: the flag clears only on CONFIRMED wins (active_size ==
fitted), reclaim retries per keystroke (1s throttle), and the
rebroadcast-of-what-we-drew case explicitly re-arms.

**One way back.** The chrome bar's chevron sat beside a title menu that
also carried "All sessions…" — two adjacent ways back reading as
unfinished work. The menu row is gone; the chevron is the way out.

**Keyboard-app question, answered:** no to a system keyboard extension.
It can't auto-activate per-app (the HOST chooses keyboards, not the
extension), needs Settings enrollment plus globe-key switching, and runs
in a sandbox that can't see hop's state. The accessory bar already IS the
"hop mode only when needed" behaviour — in-app, zero friction. If more
keys are wanted, the bar grows (second row, long-press combos); the
native ceiling for in-app input is a full custom inputView, still without
any extension.

Suites: 62 unit, 17 UI, green.

## Colour, and the wall goes to the glass (iteration 149)

Jian: "better - continue!" Then, mid-round: some tiles stay "…", the left
and right borders are wasted, and the You/Agents/All row "does not need to
occupy that much space."

**Tiles are real miniatures now.** /preview's `color` field turns out to be
rows of runs with palette already resolved to hex ({t, f, b, o}) — the
daemon did the ANSI work, so TileInk is forty lines of decode + an
AttributedString builder, no parser. Purple comments, blue paths, dim
status lines at reduced opacity, even diff-highlight backgrounds render in
the tiles. TileTypography went range-based so the coloured render and the
plain fallback show the same rows by construction; sessions without colour
(no persistent terminal) fall back to plain automatically.

**The "…" tiles were a starvation bug, not slowness.** refreshPreviews
took prefix(8) of a list whose order never changed between polls; tile
mode's LazyVGrid keeps 10+ cells alive, so the same tiles missed the
budget every tick, forever. Budget is 12 now, and the off-screen tail
rotates a little each poll so the whole fleet takes turns.

**Space:** contentMargins pulls the wall to ~6pt of the glass (the
inset-grouped sides spent ~20pt each saying nothing). Scope became a
toolbar dropdown — Picker in a Menu, system checkmarks for free — and the
row it occupied is gone; the fleet summary is a quiet clear-background
line under the bar.

**Badges scan by colour:** appTint() — claude keeps purple, editors teal,
python blue, node green, ssh amber, unknown neutral. Both modes share it.

Suites: 61 unit (4 new), 17 UI, green.

## The design pass: depth, light, typography (iteration 148)

Jian, after 147: "it is better now but you can still do better! i found you
to be a really good web designer, channel some of that skill to this."

What changed, in the language of that craft:

- **Cards are lit objects now, not filled rects.** Tiles carry a gradient
  surface (top edge catches the light, falls to the page dark), a hairline
  stroke that fades downward, and a soft drop shadow for lift. Radius up to
  14. Flat fills next to these read as holes — hopCard/hopHairline are
  tokens now so other surfaces can join.
- **State is glow.** Dots bloom in their own colour (new hopLive/hopDead
  tones instead of traffic-light .green/.red); a session wanting you wears
  amber in the ring, the header wash, and the shadow itself. List rows got
  the same dot treatment.
- **The one control everyone sees first is no longer stock.** You/Agents/All
  is capsule chips — purple marks selection, hop's accent doing actual work
  — replacing the default-issue segmented control.
- **The dead zone died.** Inset-grouped defaults spent ~140pt above the
  first control; contentMargins + listSectionSpacing pulled the wall above
  the fold — six full tiles on the first screen.
- The chrome pill gained its hairline and shadow: it reads as a floating
  object instead of a smear of material.

Suites stayed green through the whole pass (57 unit / 17 UI); screenshot
tour re-run after every visual change, temp test excised after.

## Real estate, and chrome that finally leaves the terminal alone (iteration 147)

Jian's verdict on tile view: sleek, but the font was really small and the
tagline was missing. Then two more, mid-round: "we are not using screen real
estate efficiently. This is a terminal app" — and the top menu "showing and
hiding messes up the terminal, also that menu to be honest is not well
thought out." Three complaints, one round.

**Tiles read now.** The first build scaled the whole screen to the tile —
90 columns in a half-width tile is ~3pt, texture not text. TileTypography
holds a 7pt floor: scale-to-fit until the floor binds, then show LESS screen
instead of smaller glyphs — trailing blanks trimmed first, then history from
the top, so the tile keeps the live bottom rows. The right edge clips; line
starts carry the information. And the tagline is back as a constant-height
footer (cwd when a session has none) — it was the one line Jian reached for.

**The terminal has no navigation bar anymore. At all.** The old design
toggled the bar, and every toggle resized the terminal — which reflows the
shared PTY mid-read. Measured in the fix's screenshots: chrome shown and
chrome hidden, same text at the same pixels. Chrome is a floating translucent
pill (back · title/switcher · ⋯) OVER the grid; showing it costs a
glance-through, not a reflow. Tap the strip to summon, tap the bar's empty
background (or wait 3s) to dismiss. List title went inline (~50pt back),
tile grid tightened to 8pt gutters, terminal side margins 5→2.

**The menu got thought out.** Twelve items in arrival order became four
sections by what an item acts ON: content (find/copy/links), View
(fit/size/theme), Sharing (viewers/lock/control), connection (reconnect).

**The swipe back nearly died, and the autopsy mattered.** With the bar gone
for good, SwiftUI keeps its interactive pop recognizer disabled — claiming
the delegate (BackSwipe.swift's whole job) and even forcing isEnabled every
layout does nothing. The terminal now carries its own
UIScreenEdgePanGestureRecognizer that dismisses on begin. Two traps en
route: (1) an edge pan IS a UIPanGestureRecognizer, so our own
vertical-dominance gate in gestureRecognizerShouldBegin was rejecting the
new recognizer before it could fire — exempted explicitly; (2) the first
post-change UI run showed TWO failures, but one was the documented sim
rotation wedge (reboot cleared it) — rerunning before diagnosing saved an
afternoon of chasing a ghost.

Suites: 57 unit (3 new for TileTypography), 17 UI, green.

## Tiles or list: the user chooses (iteration 146)

Jian: conflicted between the web switcher's tile wall and the app's list —
"can we allow user to choose? i think our session switcher UI is neither very
aesthetically well designed nor using the space efficiently."

Both now exist and the choice is a toggle (⋯ → Tile view, persisted). Tile
mode is the web wall's shape natively: a two-column grid where every tile is
the session's WHOLE screen as monospaced text, scaled to the session's true
column count, under a slim header with the name, state dot and app badge.
Attention wears an amber ring and header wash. Six live screens fit where the
list showed two and a half rows. Long-press a tile for the full context menu
(reply, rename, kill, agent access); tap opens the terminal.

Engineering notes:
- One fetch feeds both modes. /preview turns out to return the WHOLE screen
  as plain text plus its grid dimensions — the rows take their three
  meaningful lines from it, tiles take all of it. The first tile build used
  /screen and rendered its escape sequences as literal "[38;2m" confetti;
  the fix was choosing the right endpoint, not writing an ANSI stripper.
- Tiles use Button + path.append, not NavigationLink — List decorates nested
  NavigationLinks with disclosure chevrons, one per tile.
- The list keeps what tiles cannot offer: taglines, swipe actions, grouping.
  Neither mode is objectively right, which is exactly why it's a toggle.

## The backspace, restored — and how two ⌫ keys fooled us both (iteration 145)

Jian, from the phone: hold-to-delete DISAPPEARED after the ⌫ removal. That
report unravels iteration 123's premise. The "system delete repeats on
hardware" observation was made on build 153 — where the bar's repeating ⌫ sat
one row above the system delete. Two ⌫ glyphs, one thumb: the key being held
was almost certainly MINE. The simulator measurement (one character per held
system delete) was right all along; the testimony and the measurement were
about different keys, and I retired the measurement instead of running a
discriminator — with both keys on screen, "which one are you holding?" was a
one-line question never asked.

⌫ is back, past the fold, hold-to-repeat intact, with the story in a comment
and a tombstone test. The lesson joins the traps list in spirit: testimony
and measurement disagreeing means the EXPERIMENT differs, not that one of
them is wrong.

## Fit to width lands: the whole desk grid on one phone screen (iteration 144)

The observer mode offered in the viewport answer is real now. `⋯ → Fit to
width` shrinks the type until the peer's full grid width fits — the verified
case renders a 90-column ruler on one unwrapped line — and flips back via
`Actual size`. While it is on, the phone claims NOTHING: not on layout, not
even on typing (you chose to watch; keystrokes go into their layout, which is
what answering a prompt on the desk's screen means).

Getting the width right took three attempts, each caught by the ruler:
1. Analytic font scaling from measured glyph advances fit 84 of 90 columns —
   SwiftTerm rounds cell widths differently than NSString measures them.
2. A measure-at-candidate refinement loop still landed at 84 for the same
   reason: any calculation trusts the wrong metric.
3. The fix that works: converge on SwiftTerm's OWN reported column count —
   nudge the font 3% smaller (bounded at 8 nudges) until sizeChanged reports
   at least the elected width, then snap the grid to the exact elected size.
   The observable you converge on must be the one that decides the outcome.

## The peer-size flap: found under the fit-width work, fixed at the root (iteration 143)

Building the fit-width observer mode surfaced a pre-existing bug that is very
likely the roughness behind Jian's original "mobile does not handle the other
user's size well": while a desk holds the session, the phone's grid FLAPPED
51↔90 every ~3 seconds, forever. The cycle: adopt the elected size → any
layout event (keyboard, rotation) refits the terminal and re-sends our fitted
size → the server rejects it (the desk is typing) and re-broadcasts
active_size → adopt again. Measured on the shipped build: 6+ adopts in 20s,
indefinitely.

Fix follows hop's own rule — size follows TYPING. After adopting a peer's
size, layout changes no longer re-send ours; the reclaim rides on the next
real keystroke (fitted size sent alongside it, so the terminal snaps back the
moment the user engages). Verified with the probe: two adopts at attach (join
+ the one deliberate claim's answer), then silence for the rest of the hold.

The fit-width (observer mode) feature itself is STASHED, not landed: its
wiring amplified the flap 60× before the root cause was understood, and it
deserves a clean round on top of this fix. The pure fitFontSize maths and its
tests are in the stash with it.

## Upkeep tick: TSan clean (iteration 142b)

`make tsan` — attach, drag, reconnect, session-switch under Thread Sanitizer
against live sessions: **0 races**. First run of the target since it was
created; everything socket-adjacent that landed after the #112 race fixes
(ended-session latch, existence check on reconnect, receive tidy-up) is
covered by it. Baseline current.

## Upkeep tick: no upstream drift, suites green on the churned fleet (iteration 142)

- hop2 has had **zero server-side commits** since the protocol audit — the
  recent work (taglines, switcher filtering) is web-client only. The WS/API
  contract this app is built against is unmoved.
- Both suites green against today's fleet, which has churned several new
  sessions in: 52 unit, 17 UI (1 skipped by design).

Nothing to change; recorded so the next fire knows the baseline date.

## Plan v2: the boundary items carried to the boundary (iteration 141)

With verification exhausted, the remaining autonomous value was at the hop2
boundary — carried as far as the boundary allows:

- **HOP2-NOTES.md** now holds the ready-to-apply patch for the size-election
  bug (scrolling counts as typing; a phone reading claude steals the size from
  a desk that's typing), with an anchored-regex fix, the reasoning, and a
  verification recipe using tools/probe.mjs. One read for Solstice, zero
  archaeology.
- The same note narrows the preview-corruption bug's blast radius with this
  week's measurement: previews are clean (grid path); only getOutputSince
  consumers are affected. The mobile-track urgency flag is withdrawn.
- **The PWA-push mandate item is formally retired**, not silently ignored: it
  was the hedge for a world where the native app failed. The native app is
  installed and verified; APNS-PLAN.md is the push path.

## The banner reply, driven for real (iteration 140)

The one headline feature never exercised end to end was the REPLY action on a
bell notification — the lock-screen answer that motivated half the
notification design. Driven now, with the probe from tools/: a real BEL, the
banner long-pressed in springboard, "ok-from-banner" typed into the
notification's own reply field, Send — and the text arrived in the session's
PTY with its newline, confirmed from the daemon's screen API.

That closes the full attention loop in both directions: the session can reach
the human (bell → banner, #131) and the human can answer without unlocking
anything (banner → PTY, this entry). Screenshots of the expanded banner and
the typed reply are in the round's record.

Every headline feature has now been driven end to end with real
infrastructure: scroll and pan against live grids, bells, banner tap, banner
reply, copy, find, login failure, parked semantics, resurrection guards.

## The last tail items (iteration 139)

**System-light appearance: already correct.** The whole UI is pinned dark via
`.preferredColorScheme(.dark)` — screenshot under system-light is identical
hop. Checked so it is never re-checked; the deliberate single-look is the
design.

**The switcher got its escape hatch.** The menu caps at twelve and the fleet
runs nineteen, so the session you want is regularly not in it — and the way
out was dismiss-the-menu, then back: two taps to discover the menu couldn't
help. "All sessions…" at the menu's foot makes it one tap to the list.
Covered by the permanent switcher test.

The autonomous tail is now: baseline upkeep only. Everything else on the board
is Jian's — the ranked list in #137 stands.

## Maintenance tick: two tail items closed by measurement (iteration 138)

**Preview corruption: stale for this app — item crossed off.** Scanned all 20
live previews: zero raw ESC bytes, and every "stripped-escape fragment" the
scanner flagged was a false positive ("Cooked for 6m 21s", "250ms" — minutes
and milliseconds, not escape remnants). The grid-preview architecture renders
previews server-side from persistent terminals, so the getOutputSince
mid-escape reset-tail bug — still unfixed in hop2 — does not reach the preview
endpoint this app uses. Client-side hardening would have been building for a
bug that does not manifest here. (The hop2 bug itself remains Solstice's,
for the paths that DO use getOutputSince.)

**Strict-concurrency baseline: holds at 6**, the same inherent set (deinit
timers, SwiftTerm's nonisolated delegate) after all the rounds since #112c.

## The plan, ranked (iteration 137)

Everything interactive is audited; what remains is either gated or optional.
Ranked so the next session (or the next loop fire) picks by value, not
momentum:

**Yours, in unblocking order:**
1. **Device checklist** — four items only hardware answers: coast feel at
   120Hz, the `background:` line in Copy diagnostics (decides how urgent APNs
   is), ctrl combos on a hardware keyboard, walking out of wifi.
2. **App Store record + one distribution cert** (STATUS #133 has the exact
   steps) → `make testflight` becomes one command.
3. **APNs greenlight** → APNS-PLAN.md executes against hop2, with Solstice.
4. **One-line decision**: mark archived sessions as stopped in the list, or
   leave them transparent?

**Autonomous, if the loop keeps running (descending value):**
- The switcher menu's 12-cap UX when the fleet outgrows it (a "More…" tail
  into the list, if fleet growth continues).
- Periodic re-run of `make strict` / `make tsan` after SwiftTerm updates.
- Keep the idle-CPU baseline honest after any poll-loop change.

**Consistency fix shipped with this entry:** parked sessions no longer appear
in the in-terminal switcher menu. Parking hides a session from browsing and
silences its bells; the switcher offering it anyway made "not my working set"
mean three different things in three places. Pure function, unit-tested.

## The harness moves into the repo (iteration 136)

Two days of verification built up eight near-identical probe scripts in a
session-scoped scratchpad that dies with the session. Consolidated into
`tools/probe.mjs` — ring / fill / type / clear / hold-size, one file, header-
documented — and verified live before committing: fill put END-MARKER on a
scratch session's screen, ring took its bellSeq 0 → 1.

`tools/README.md` carries what cost the most to learn: the four patterns that
produce trustworthy evidence (in-test screenshots, marker-file choreography,
controls, discriminators) and the traps table — pbpaste lies, XCUITest
delivers mods=0, the system keyboard's repeat never fires under a synthetic
hold, sim rotation wedges, grep eats make's exit code, regex-edited probes
fail silently. Each line in that table cost real time this session; the next
session should only have to read it.

## VoiceOver keeps the chrome, and an idle-CPU baseline (iteration 135)

An adversarial read of my own hidden-chrome design found who it locks out:
VoiceOver users. The chrome auto-hides, and both ways back — a tap on an
unmarked strip, a drag toward the live edge — are gestures VoiceOver cannot
see. For a VoiceOver user the hidden bar is not minimal, it is GONE, with the
back button, the switcher and every terminal action inside it. The auto-hide
now skips entirely when VoiceOver is running. Not drivable by XCUITest (it
cannot enable VoiceOver); the guard is three lines and reasoned, and the
device checklist's VoiceOver item covers the rest.

Idle CPU baseline, recorded so a future regression has something to regress
FROM (simulator, Release-logic Debug build, 10 samples over 30s each):
- In a terminal, idle: ~0%, one 7.9% spike on an output burst.
- On the list (20 sessions, previews polling): ~0%, one 3.9% spike on a poll
  tick. The 5s/9s poll loops cost nothing measurable between ticks.

## A "regression" that was the simulator, and one real improvement (iteration 134b)

The landscape test failed twice in a row after the notification-body change —
unrelated code, so it looked like a mystery regression. The in-test screenshot
settled it: the app was not rotating at all. Orientations were declared,
the code was unchanged — the SIMULATOR's rotation state was stuck after hours
of temp tests, and a reboot fixed it (the test then passed in 5 seconds).
Lesson filed with the others: when a UI test fails on untouched code, suspect
the simulator before the app.

Kept from the diagnosis, because it matches the landscape rule: rotating to
landscape now dismisses the chrome immediately instead of waiting out the 3s
timer — every point to the terminal the moment the phone turns. The top strip
still summons it.

## Notification bodies say the message, not the prompt (iteration 134)

The bell drive in #131 left one nit on record: the banner's body was
"jianzhou@MED-GEN-ML-15 hop2 %" — the prompt that returned after printf — when
the thing worth waking a phone for was "answer me" one line above.

The body picker is now a pure function that takes the last line the session
SAID, skipping prompt-shaped lines. A prompt is recognised narrowly — ends in
%, $ or # AND contains '@' (the user@host shape), or a bare ❯ composer — so
"CPU 97%" is kept while "jian@host dir %" is skipped. If everything looks like
a prompt, the last line ships anyway: a wrong-ish body beats an empty
notification. Unit-tested, including the exact case from the bell drive.

## TestFlight dry run: one real bug fixed, two blockers mapped (iteration 133)

Ran the archive/export pipeline end to end BEFORE Jian's first click, stopping
short of upload. Findings:

**Fixed: `make testflight` was archiving a DEBUG build.** The scheme never
specified an archive configuration and XcodeGen's default turned out to be
Debug — an unoptimised binary headed for TestFlight. The scheme now pins
`archive: Release` (verified in the generated xcscheme). Note: the archive
STAGE showing `aps-environment=development` is normal — archives sign with the
development profile; the export re-signs for App Store.

**Blocker 1 (known): no app record.** The ASC API confirms it live: bundle
`io.zhoulab.hop.spike` is registered, the apps list is empty. App Store
Connect → Apps → + → New App remains the ask.

**Blocker 2 (new): cloud signing is refused.** Local export fails with
"Cloud signing permission error / No profiles for 'io.zhoulab.hop.spike'".
The API key (CCFL4WD4V4) reads fine but cannot mint an Apple Distribution
certificate. One of, whichever Jian prefers:
  - give that ASC key Admin role (cloud-managed distribution certs need it), or
  - create one Apple Distribution certificate once (Xcode → Settings →
    Accounts after signing in, or developer.apple.com → Certificates); after
    that, automatic signing can use it and `make testflight` proceeds.

ExportOptions uses `destination: upload`, so once both blockers clear, the one
command really is archive → upload.

## Login failure path: verified against the real daemon, once (iteration 132)

A deliberate bad login — exactly ONE, because hop locks an IP after five
failures and the simulator shares the outbound IP with Jian's phone — driven
through the full flow: sign out, wrong password, wrong code, Connect.

The daemon's own reason ("Invalid password") reaches the screen in red, the
password field clears, and Connect disables until the fields are refilled.
Screenshot kept. The failure counter was checked in hop's source BEFORE
spending any attempts: 5 failures → 30s lock, doubling; a successful login
resets it.

Not kept as a permanent test: each run costs a real login failure against the
shared IP budget and drives a sign-out. The navigation it uses is already
covered by the sign-out test; the error rendering is verified here, by
evidence.

## The core promise, driven end to end with a real bell (iteration 131)

Every attention feature had been verified in pieces or through the
HOP_DEV_ATTENTION flag. This round drove the real thing, no forcing: a probe
ran `printf 'answer me \a'` in a scratch session's PTY while the app sat on
the list with notifications freshly authorized (first-run offer → system
dialog → Allow, all driven).

One screenshot holds the whole pipeline: the banner (session name, tagline as
subtitle, last output line as body), the summary flipped to amber "1 wants
you", the row washed amber with the attention dot and sorted to the top — and
the test then tapped the BANNER and asserted it landed in that session, which
it did. BEL → bellSeq → poll → attention → notification → banner → tap →
the right terminal: all real, all in one run.

The first attempt failed and the failure was the harness again: the ring probe
was built by regex-editing an old script, the substitution silently didn't
match, and no BEL was ever sent — while the app correctly showed "nothing
waiting on you" and I nearly read it as the app's bug. bellSeq: 0 from the
daemon settled it. Probes are written as whole files now, never regex-derived.

Not kept as a permanent test: it needs an externally-timed ring and springboard
choreography. The screenshots and this entry are the record.

## Copy flows audited: correct, with one honest caveat added (iteration 130)

Both copies verified against a fixture session with known content (61 numbered
lines), sizes read from the app's own log because the simulator's pbpaste
lies (returned 1 byte while the app had copied 452 chars):

- Copy screen: the visible rows, trimmed. Correct.
- Copy all: the entire buffer, screen included — 453 chars ≥ the screen's 452,
  the superset property that makes "all" mean all. Correct **once the snapshot
  has landed.**

The one real finding: copy-all in the first seconds after opening a session
copies whatever has arrived — measured 300 of 453 chars — and LOOKS complete.
The toast now says "Copied — history still syncing" until the snapshot lands,
instead of letting a partial copy pass as the whole thing. Copy sizes stay in
the log for diagnostics.

## Replying to a dead session: predicted bug, measured absent (iteration 129)

The reply sheet's worst case on paper: the target dies mid-compose, Send opens
a fresh socket to the dead name, hop creates rooms on demand — the
resurrection bug through a third door, with the reply EXECUTING in a fresh
shell as a bonus.

Staged it for real on the current build: scratch session, reply sheet open,
killed from outside during compose, then Send. **It stayed dead.** The daemon
404s a WS attach to a name it doesn't know; the #118 zombie needed the
reconnect path with durable meta behind it, and that door is closed. QuickReply
surfaces the failure as "couldn't send", which is the right outcome.

Recorded because the alternative was shipping a guard for a bug that does not
exist — this session's recurring lesson pointed the other way for once:
evidence first, and the evidence said no.

## Find was typing into the session (iteration 128)

Audit of the find bar under hidden chrome caught something worse than layout:
opening Find left the keyboard bound to the TERMINAL. Type your search term
and it went into the live session — the screenshot shows "keyboard" sitting in
a claude composer while the find field displays its placeholder. A search
that quietly feeds an agent's prompt is an input leak, not a nuisance.

Find now focuses its field the moment it opens (FocusState), and Done releases
it. The permanent test asserts on the FIELD's value after typing — which keeps
it clear of the flaky match-toast territory that kept find untested before.

The stray "keyboard" the audit typed into Orion's composer was erased with
exactly eight deletes over a throwaway socket.

## Light mode had never been looked at (iteration 127)

The light terminal palette landed weeks ago and the bg=ffffff announcement fix
yesterday — and no one had ever LOOKED at light mode. Screenshot audit found
the white terminal floating letterboxed in near-black bands: the strips around
the terminal (padding, safe areas) were hardcoded to hopSurface, which is the
DARK background's exact hex. They follow the terminal's theme now; dark mode
is unchanged by construction.

What the audit could NOT fix, recorded so it isn't chased: an existing session
keeps painting dark-theme colors on the white background, because claude picks
its theme from the terminal's answer at ITS startup (hop 2522c3e). A session
started while a light client is attached paints light. That is hop's design,
not an iOS bug.

## The bell you couldn't reach (iteration 126)

List-screen interaction audit, first find: the summary line can read
"1 wants you (1 not shown here)" — precisely when scope or filter hides the
ringing session — and offered no way to reach it. The app announcing a bell
while hiding the session is the worst version of its core promise.

The summary is now a button when anything wants you: tapping it opens the
longest-standing wanting session directly, fleet-wide, deliberately ignoring
scope and filter (which are exactly what can be hiding it). Same navigation
path a notification tap takes.

Permanent UI test, deterministic via the dev flags (force attention + a
filter that matches nothing). Getting it green taught two things worth keeping:

- `.accessibilityLabel` on a button REPLACES its text in the accessibility
  tree. VoiceOver would have said "Open the session that wants you" and never
  the counts. It's a `.accessibilityHint` now — the text is the label, the
  action is the hint.
- `HOP_DEV_ATTENTION` forced `raw.first`, and the fleet reorders by activity —
  a port or parked session at the top made the flag force nothing. It now
  forces the first alertable session.

Also kept: a per-refresh log line ("refresh: 20 sessions, wanting 1"), which
is what proved the model was right while the UI query was wrong.

## Vertical reach on a peer-sized grid: verified, with a surprise (iteration 125)

Staged the vertical twin of the RIGHT-EDGE experiment: a 90x44 probe fills its
screen so the last line (BOTTOM-MARKER) and the prompt sit on rows the phone
cannot draw, then the phone attaches and drags up.

The surprise: the BEFORE screenshot already showed the bottom. SwiftTerm
follows the CURSOR, so on attach the view parks at the bottom of the peer's
grid — marker, prompt and cursor all visible with no gesture at all. The drag
then had nothing below to reveal (already clamped at maxY), which is why the
before and after screenshots are byte-identical.

That is the right default and it closes #96's actual fear twice over: the
bottom of a peer's screen — where claude's input box lives — is what you SEE
ON ARRIVAL, and panning covers everything else. Horizontal pan remains the
screenshot-verified case; vertical shares panBy and its clamp maths, and its
destination is now proven reachable by the attach itself.

## Keyboard audit round: two null results, recorded (iteration 124)

- **Text-input traits are already right.** SwiftTerm sets autocorrection,
  spell-check, smart quotes, smart dashes and smart insert-delete to `.no` and
  autocapitalization to `.none` — so `'` arrives as 0x27, not `’`, and
  double-space cannot become ". ". Checked at the source; do not re-audit.
  (One matrix cell overstated: with autocorrection off there IS no autocorrect
  — the native win is dictation and the real keys, not correction.)
- **The arrow keys cannot get bigger.** 40pt and 38pt were both tried after
  ⌫'s removal freed width; both push → off the first screen — the "spare" was
  already funding the ⇞ peek that hints at the scrollable tail. Fatter arrows
  means thinner esc/tab/ctrl: the same miss rate, moved. 34pt stands, by
  measurement rather than taste.

Phone verified on build 154 from the device itself
(`devicectl device info apps` → bundleVersion 154).

## The backspace key is gone, on device evidence (iteration 123)

Jian, from the phone: holding the SYSTEM keyboard's delete repeats on real
hardware. The simulator measurement that justified adding ⌫ — one character
per 2.5-second hold — was an XCUITest artifact: a synthetic press never
drives the keyboard's own repeat timer. So ⌫ was redundant as a tap AND as a
hold, and it is removed. The bar is back to exactly the keys the system
keyboard cannot produce in any plane.

The lesson joins the pile from this session: the harness lied about hardware
ctrl combos (mods=0), about menus in overlays (a fixture had drifted), and now
about key repeat. A simulator measurement of KEYBOARD behaviour is evidence
about the simulator.

## Peer-sized grids: adopt and PAN, like hop's mobile web (iteration 122)

Jian: "mobile does not seem to handle the case where the terminal is fitted to
the other user's size well. you should take the hop mobile terminal ui as the
reference for such behaviors (scroll = panning in that mode)".

This reverses #96, which refused a peer's size and let output wrap into mush.
The web's answer was always adopt-and-pan; what #96 was missing is the pan,
which is what makes the clipped region — claude's input box lives at the
bottom — reachable.

Now: when the room elects a size bigger than this screen draws, the terminal
adopts it, and drags become 1:1 two-axis PANNING with momentum. Scroll-as-
wheel and scrollback return the moment the grid fits again.

Two SwiftTerm fights, both found by measurement:

- `updateScroller` recomputes contentSize lazily; after a programmatic resize
  it still said 391pt of content for a 90-column grid, so every pan clamped to
  zero. The grid's true extent is now computed from what we draw before each
  pan.
- `updateScroller` also runs on EVERY output and pins the offset back to x=0
  and the live row — a pan was undone within one keystroke from the desk. The
  pan is stored as a delta and re-applied after each output chunk.

Verified with the test writing its own screenshots (after two rounds lost to
racing an outside screenshot against test teardown): a 90x44 probe holds the
election while typing every 1.5s; the phone shows the 90-col ruler unwrapped
and clipped; a swipe reveals RIGHT-EDGE at column 90; and six seconds of desk
typing later the pan is still there. Horizontal is screenshot-verified;
vertical panning (the bottom rows of a taller grid) shares the same path but
is verified only by the clamp math.

### Keyboard (iteration 121b)

- ⌫ moved past the fold: a TAP is redundant with the system delete — it exists
  only because a HELD system delete sends one character to a custom key-input
  view (measured), so it is the only backspace that can repeat. Putting it
  mid-bar had broken the documented promise that esc…→ fit without scrolling.
  **Open question for Jian: hold the system delete key on the phone. If it
  auto-repeats on real hardware, the measurement was a harness artifact and ⌫
  should be deleted outright.**
- The bar cannot follow the system keyboard's caps/123 toggle: iOS exposes the
  keyboard's plane only to keyboard extensions (`textDocumentProxy`), never to
  an app's accessory view. By design the bar holds only keys that exist in NO
  plane — that is why | / - ~ were removed.

## Chrome hidden by default: 23 rows → 27 (iteration 121)

Jian: "screen realestate is limited in mobile ideally most unnecesaary ui
comoonents are hidden by eefaul to make room for termjnal".

The navigation bar is gone by default in BOTH orientations now (it already was
in landscape). Measured: **51x23 → 51x27**. Four lines, a 17% taller terminal,
on every session.

It comes back when you tap the top 46pt of the terminal — where anyone reaches
for controls, and the one place a tap is not meant as "give me the keyboard".
The back SWIPE still works because `BackSwipe.swift` re-enables the gesture
UIKit ties to the navigation bar.

**The honest trade.** The controls stayed in the navigation bar rather than
moving to an overlay of my own, so summoning them changes the terminal's row
count and briefly reflows the shared PTY. An overlay would avoid that — I tried
three times, mangled the file twice, and reverted. The phone already reflows on
every attach, and the size election hands the size back the moment someone
types at a desk, so the cost is small and bounded. It is written down rather
than hidden.

Two things this cost, worth remembering:

- The top strip's tap test failed for an hour because SwiftTerm's view is a
  SCROLL view: `location(in:)` carries the scrollback offset, and a tap at the
  top of the screen reported y=461. The strip means bounds.origin, not zero.
- Chrome that moves on a timer breaks XCUITest, which resolves elements against
  a moving target and reports the miss as whatever assertion came next. The bar
  now stays put under `-hop-ui-testing`, the same argument that already steadies
  the caret for the same reason.

Also fixed here: `testDragScrollsAndLiveButtonReturns` pointed at
`presenceprobe`, which no longer exists — and it had only ever passed because
attaching to a dead name CREATED it, which is the resurrection bug from #118.
It now points at a live shell and SKIPS when the fixture is missing, because
that is an environment fact rather than a regression.

## Backspace, and the flake that cost a feature (iteration 120)

Jian: "long press a key especially backspace should repeat".

**Measured first.** Holding the system keyboard's delete for 2.5 seconds sends
**one** character to this terminal — iOS repeats delete only for its own text
views, not for a custom key-input responder. So correcting a mistyped path
meant one tap per character.

Added ⌫ to the key bar, where the repeat is ours: the same hold now sends
**36**. Sequence 0x7f, taken from what the system key actually sends (logged,
not looked up). Still deliberately not repeating: ^C, paste, esc — a stuck
interrupt is destructive in a way a repeated delete is not.

### The flake, finally named

`testSwitchSessionFromTheTitleMenu` expected a menu entry called "Solstice".
The switcher lists the **twelve most recent** sessions, and Solstice had
drifted to **fourteenth** — so the test went red and read exactly like "the
menu never opened". That is the ~1-in-4 flake from #107 that could not be
named at the time.

It cost more than a red test. Jian asked for chrome to be hidden so the
terminal gets the room, and the floating-bar implementation of that was
**reverted on the strength of this misreading** — I took the failure as proof
that a Menu does not open from an overlay, when the menu had been opening all
along.

The test now proves only what it can prove deterministically: that tapping the
session name opens the switcher. Naming a target needs either a scratch
session on every run or the fleet's current order, which is the thing that
broke it.

## The same zombie, through the other door (iteration 119)

#118 latched "this session ended" when the message ARRIVES. A phone in a
pocket may never receive it: iOS suspends the socket, the session is killed at
the desk, and returning to the app reconnects — which for hop means creating
the room again. Same zombie, different door.

`reconnectIfNeeded` now refreshes the session list and refuses to attach to a
name that is no longer in it. Refreshed rather than trusted, because the stale
copy is exactly what would still list the dead session. If the refresh fails,
or nothing has ever been fetched, it proceeds — refusing to reconnect on no
evidence would be worse than the bug.

**Honest about what the test proved.** Backgrounding via another app, killing
the session, and returning gave the right outcome — not resurrected, fleet
still 19, red dot, correct card, keyboard dismissed — but the card said
"Session terminated", which is the message from the SOCKET. iOS had kept it
alive long enough to deliver `session_ended`, so this run exercised the latch
from #118, not the new check. The simulator "never truly suspends" (the same
line the device checklist has carried since #50), so the path this change
exists for cannot be reproduced here. It is reasoned, cheap, and cannot make
things worse; it is not verified.

## Finishing what the resurrection fix started (iteration 118b)

Screenshotted an ended session against the fixed build, and all three symptoms
from #118 are gone: the status dot is RED, there is no "connection lost" line
stacked under "[Session terminated]", and there is no live shell behind the
card. One bug, three symptoms, one fix.

The fix then exposed something it had been hiding. Typing into an ended
session still buffered the keystrokes and toasted "Reconnecting — input
buffered" — which was true while the app resurrected sessions, and became a
lie the moment it correctly stopped. The whole worth of that message is that
the promise gets kept. It now says "Session has ended" and keeps nothing, and
the keyboard is put away when the session goes, because there is nothing left
to type into.

## The phone was resurrecting killed sessions (iteration 118)

The worst bug found today, and it took opening a session and killing it from
somewhere else to see — no test would have.

hop creates a room on demand for any attach. So when a session ended, the
app's automatic retry did not fail to find it: it **created it**. Kill a
session at your desk with your phone open on it, and the phone quietly brought
back a fresh shell under the same name. Measured directly: fleet 19 → 20, with
a live `endtest` and a new prompt sitting where the agent had been.

The screenshot showed all three symptoms at once and I nearly filed them as
three separate polish items — a stale green status dot, a red "connection
lost" line stacked under "[Session terminated]", and a live shell behind the
"Session ended" card. They were one bug: the app had successfully reconnected
to a session that no longer existed.

hop's web client has always known this — `shouldReconnect = false` on
`session_ended`. The iOS client now latches the same thing, and it blocks
EVERY reconnect path, not just the automatic retry: returning to the
foreground and a route change run through the same door, and neither should
resurrect a session either. The way back is the list.

Verified by repeating the experiment against the fixed build: killed while
open, `endtest2` stayed dead. (The fleet showed 20 for a moment afterwards
because the OLD build was still running when the previous session was deleted
and resurrected it one final time — which is the bug demonstrating itself
twice.)

## What a brand-new install sees (iteration 117)

Wiped the app entirely — no defaults, no keychain, no seen-bell baselines —
and pointed it at the live fleet, where three sessions had already rung
(Solstice 48, presenceprobe 24, rooms 5).

It showed **"19 sessions · nothing waiting on you"**, and the preferences file
confirms baselines seeded at exactly 48 / 24 / 5. A new device does not
inherit a fleet's history as a pile of unread bells — which is what
`rebaselinedMarker` exists for, unit-tested since #40 but never once run
against real data with real counters.

Also confirmed in the same run: the notification opt-in is the first thing a
fresh install asks, which is right for an app whose entire point is being told
when an agent wants you, and the viewport-aware previews from #116 are
populating the visible rows.

## Previews now follow your eyes (iteration 116)

A preview — the three lines of what a session is actually SAYING — is the most
useful thing on a row. They cost the daemon a render each, so the budget is
small and fixed, and it was being spent on the first six of the rendered list,
full stop.

With nineteen sessions that means two-thirds of the fleet shows a name and no
output, and **scrolling never changed it**: the rows under your thumb stayed
blank while six off-screen ones stayed fresh.

Rows now report whether they are on screen, and the budget is spent on the
visible ones first, falling back to rendered order to fill. Same cost to the
daemon, pointed where the eyes are. Raised 6 → 8 at the same time, because a
phone screen holds about seven rows and a budget smaller than a screenful is
the difference between "the list shows what sessions are saying" and "most of
it doesn't".

Verified by screenshot: scrolled to rows ten through seventeen, and Bellatrix,
Neptune, presenceprobe and Altair — all of which would have been blank before
— are showing their output.

## The app now says which build it is (iteration 115)

Follows directly from #114. The phone ran an unoptimised build for its entire
life with nothing on screen saying so — while the scroll feel was being judged
on it. "This feels sluggish" and "this is a debug build" are the same sentence,
and it should never have to be inferred.

`⋯ → Server & account` now reads `1.0 (142) · cbef4ab · debug`, with the
suffix absent on Release. Confirmed by screenshot, including that the longer
string still fits on one line.

## The phone has been running an unoptimised build all along (iteration 114)

Measured what a firehose costs, since watching agent output is what this app
IS. 13 MB in one burst (200k lines) into an attached session:

- CPU pegged at ~115% for about 6.5 seconds, then flat.
- RSS +14 MB, and **stable afterwards** — the 5000-line cap holds, nothing
  grows without bound.

Then noticed what that measurement was actually of. `make install` built the
default configuration and installed from `Debug-iphoneos`. Swift Debug is
`-Onone`: the terminal parser, the scroll maths and SwiftUI's diffing have all
been running unoptimised on the phone, every day, including while the scroll
feel was being judged.

`make install` now builds Release. `make install-debug` keeps the old path for
when a debugger is needed. The binary drops 8.6 MB → 5.1 MB.

Two details that matter:

- **APS_ENVIRONMENT is forced back to `development` for local installs.**
  Release flips it to `production` for TestFlight, and a production token
  cannot be pushed to over a development APNs connection. Verified in the
  signed app: `aps-environment = development`.
- **The dev flags are `#if DEBUG`** — deliberately, "a TestFlight build has no
  business containing it". So the Release build cannot be driven by
  HOP_DEV_COOKIE, which is why the harness keeps using Debug, and is also how
  this was discovered: the Release simulator build sat at the login screen.

Not measured: the actual speedup. Driving a Release build needs a real login,
which is the user's password. The direction is not in question — shipping
`-Onone` to a phone someone uses all day is not defensible when the flag is
free — but the number is unknown.

## Do terminals actually go away? (iteration 113)

A phone that opens twenty sessions holds twenty 5000-line buffers if leaving
one doesn't free it, and the only symptom is being killed for memory long
after the cause. The ownership reads correctly — `onEvent` captures self
weakly, the view is `weak`, the notification observer is removed on teardown —
but reading is not evidence.

So the Coordinator's `deinit` logs, and the log answers it: 4 attaches / 3
releases in one run (the fourth still open at teardown), 1 / 1 in another.
Terminals are freed.

The throwaway test that drove it was flaky — XCUITest and this app's
navigation disagreed twice — so it isn't kept. The `deinit` line is, because
it turns "does this leak" from an investigation into a grep, and its ABSENCE
is the signal.

## Two more races, and both lenses made repeatable (iteration 112c)

Thread Sanitizer over the tests that actually open, close and reopen sockets —
attach, drag, reconnect, session switch — reports **zero races**. That is the
path #112b restructured, checked by the tool that would catch a regression in
it. A normal build is also warning-free.

Strict concurrency then found two more worth fixing:

- **BackgroundRefresh held its work in a captured local `var`.** The expiration
  handler — which iOS calls on a queue of its choosing — read it while this
  thread was still assigning it. Narrow, unattended, and the kind of window
  that only ever closes on someone else's phone. The handle now lives in the
  completer, behind the lock that already serialises completion, and a task
  attached after expiry is cancelled instead of running for nothing.
- **The key-repeat timer** mutated main-isolated state from its closure. It is
  scheduled from main and fires on the main runloop, so the fix is to SAY so
  with `assumeIsolated`, which traps instead of racing if that ever stops
  being true.

Because that assertion turns a wrong assumption into a crash, holding a key is
now a UI test: 1.6 seconds on ↓, then check the app is still there. It passes,
which is also the first automated coverage of hold-to-repeat.

Both lenses are `make` targets now — `make strict` and `make tsan` — because a
check nobody can re-run is a check that only ever happens once. 11 → 6
warnings; what remains is SwiftTerm's nonisolated delegate and a deinit that
cannot touch main-isolated timers.

## A data race on the socket's own guard (iteration 112b)

Turned on `SWIFT_STRICT_CONCURRENCY=complete` — a lens the compiler provides
for free and this project had never used. 79 warnings in our sources. Most are
annotation gaps, but one was a real race, in the worst possible place.

`receiveLoop`'s completion runs on URLSession's queue, and it read
`self.generation` there — the counter that stops a RETIRED socket's callback
from triggering a reconnect, written on main by `close()`. Reading it across
threads is undefined, and a stale read brings back precisely the bug the
counter was added to fix (#46's spurious retry). The real work already hopped
to main one line at a time; the guard didn't.

Now the hop happens before any of the object's state is touched, and the
invariant is enforced rather than hoped for: `HayClient` and the Coordinator
are `@MainActor`, so the compiler checks it.

79 → 10 warnings. What's left is inherent: SwiftTerm's `TerminalViewDelegate`
is nonisolated, and a `deinit` cannot touch main-isolated timers. Not worth
contorting the code for.

Worth noting the shape: this bug was invisible to every test, would have shown
up as a rare wrong-socket reconnect on someone's phone, and cost one build
setting to find.

## The same lens again: known fix, not applied everywhere (iteration 111)

Three bugs today have had one shape — a fix this codebase already knew,
applied in some places and not others (the theme on one of three connect
paths; the auth-epoch guard on one of three fetches). So I went looking for it
deliberately.

`jsonInt` / `jsonDouble` exist because JSONSerialization hands back NSNumber
and a straight `as? Int` yields nil for the other form, silently. Two places
still cast:

- **The APNs path.** `userInfo["bellSeq"] as? Int` in the notification reply
  handler. Today that dictionary is one we build, so it holds an Int — but the
  same handler receives push payloads, where the number arrives as NSNumber.
  It would have failed the moment APNs shipped, and failed quietly: the reply
  sends, and the session keeps its dot and badge as though you had ignored it.
- **The fast paint.** `obj["cols"] as? Int` — a nil there skips the resize, and
  the symptom is exactly the wrapped mush that code exists to prevent.

Both coerced now, and the helpers themselves are finally unit-tested, including
the NSNumber-from-a-push case.

Worth noting the first one: it is a bug in a feature that does not exist yet,
found by asking "what will this handler receive when APNs lands" rather than
"what does it receive today".

## What sign-out left behind (iteration 110)

Audited what belongs to an account and what actually gets dropped when you
leave one. `signOut` cleared cookies, keychain, seen-bell baselines, the
session list, previews and the notifier — and missed three:

- `lastKnown`, the fallback used to render a session that ended while you were
  reading it. It holds names, taglines and working directories, so a stale
  entry could show one server's session details after signing into another.
- `openSession`, still pointing at a terminal on the server just left.
- `actionError` — added an hour ago, in #109. New code, same omission.

Two RACES in the same family, found by asking what else writes account data
after a request returns:

- `refreshPreviews` had no `authEpoch` guard, and a preview IS terminal
  output. A fetch in flight during sign-out landed afterwards and put the
  previous account's screen contents back into the store.
- `searchContent` likewise, and its request has a TEN-SECOND timeout, so it
  outlives a sign-out easily. Its snippets are session output too.

Both now carry the guard `refreshSessions` has had all along ("signed out
mid-flight"), which is the tell: the pattern was known and simply not applied
everywhere it was needed.

Verified by reading and by the sign-out UI test still passing — these are
races that would need a request timed to land inside a sign-out to observe,
and I would rather say that than manufacture a test that proves nothing.

## The daemon's reason vanished before it could be read (iteration 109)

Kept following the "fails without saying so" thread, this time into the other
direction: things that DO report, but not for long enough to be seen.

Every action failure — rename, kill, create, reply, agent access — was written
into `lastError`, the same field a successful refresh clears. That clearing is
right for what it was written for ("a refresh that worked is proof the last
failure is over"), and wrong for everything else: a poll succeeding proves
nothing about a rename the daemon refused as a duplicate. On wifi the poll is
every five seconds, so the verdict on something you just did was usually gone
before you finished reading the dialog close.

Split into `actionError`, which is cleared by the next attempt or by tapping
it — never by a poll.

Verified with a discriminator, both directions, against the real daemon:
creating a session whose name is already taken.

| | reason shown | still there after 12s |
|---|---|---|
| old | yes | **no — wiped by a poll** |
| fixed | yes | yes |

Kept as a permanent UI test: it has no side effects, since the create it
attempts is the one the daemon refuses.

Two throwaway attempts before that one went nowhere — the context menu and the
swipe actions both refused to open under XCUITest. The create button is a
plain toolbar button, and driving the same failure through it took one try.
When a UI probe fights back, the answer is usually a simpler entry point to
the same code path, not a better query.

## A refused bell was a silenced bell (iteration 108)

Swept the codebase for the same shape as #107 — failures hidden behind `try?`
— and found one that matters. `report(attention:)` marked a session as
notified BEFORE posting the notification, and posted it with `try?`.

So a refused notification was also a permanently silenced one: the dedupe
record said "already posted", every later poll skipped it, and that bell was
never shown at all. Failing to say an agent is waiting is this app's worst
possible outcome, and it would have happened without a trace.

The record now happens only after the post succeeds, so a failure simply
retries on the next poll five seconds later, and the refusal is logged.

The rest of the `try?` uses are fine and were checked: JSON encoding of
dictionaries built two lines above, and network calls whose failure is already
handled by the guard that follows.

## Background refresh was failing silently, every time (iteration 107)

Bells only reach a pocket if the app gets woken. Background refresh has been
implemented since #33 and shipped as though it worked. It submits its request
with `try?`.

Removing that `try?` produced, immediately:

```
background slot refused: BGTaskSchedulerErrorDomain error 1
```

Error 1 is "unavailable". **The simulator refuses BGTaskScheduler outright**,
so this particular result says nothing about the phone — but that is the
point: the failure is indistinguishable from success from here, and on a
device its only symptom is a phone that never tells you an agent rang, which
looks exactly like no agent ringing. A permanent misconfiguration (identifier
missing from BGTaskSchedulerPermittedIdentifiers, background mode absent,
Background App Refresh switched off in Settings) would fail this way forever
and silently.

So the phone can now answer it. `Copy diagnostics` carries two new fields:

    background: requested Jul 25 18:56 / ran Jul 25 19:04

`lastSchedule` records every ask (granted or refused, with the reason);
`lastRun` records the first time iOS ACTUALLY hands us a slot — the only
evidence that any of this works on real hardware. Until one lands it reads
"never ran".

Checked while there and found correct, so it isn't re-checked: registration
happens in the App's `init()` (iOS throws if it is later than launch), the
task is completed exactly once behind a lock, and the expiration handler
cancels the in-flight work.

## The bell path, verified with an actual bell (iteration 106)

Attention has only ever been exercised here through `HOP_DEV_ATTENTION=1`,
which forces the state. The thing the app EXISTS for had never been driven end
to end with a real BEL. It has now, on two scratch sessions, and both halves
of the design hold:

- **Rung after the device has seen it → attention.** `printf 'need you \a'`
  into a session the app had already listed: the daemon counted `bellSeq: 1,
  lastBellAt: true`, and the list raised "1 wants you".
- **Rung before the device has ever seen it → silent.** A second session,
  created and rung before the app ever listed it, appeared with a plain live
  dot and no attention. That is `rebaselinedMarker` doing its job: a session's
  history must not arrive as a pile of unread bells.

A screenshot mid-run also confirmed two things no assertion was checking: the
summary correctly said "1 of 21 · 1 wants you (1 not shown here)" — attention
is fleet-wide even when the list is filtered — and the server-side content
search found the term in a session's output.

The throwaway UI assertions themselves were wrong twice (`staticTexts[name]`
doesn't match how a row exposes its title, and the first "baseline" assertion
assumed a session the app had in fact already seen). Both were harness
errors; the screenshot and the daemon's own numbers were the evidence. Not
kept as tests: they need scratch sessions rung from outside, and the pure
logic underneath is already covered.

## Tidying what a day of edits left behind (iteration 105)

Two things today's work introduced and didn't clean up:

**Alt-screen was tracked twice.** `lastAltScreen` was set once from the
snapshot and read by a single diagnostic, while `RemoteModes.altScreen`
follows the stream live. The moment an app switched screens the diagnostic
would report the old value — a log that lies is worse than no log, because it
is trusted. One source of truth now, the live one.

**The scroll path built a Logger per call.** It runs on every frame of a coast
— up to 120 a second on a ProMotion phone — to emit a line that is usually
disabled. Built once now.

## Hardware keyboard: half verified, and why only half (iteration 104)

The interaction audit has listed hardware-keyboard support as "supported by
SwiftTerm, unverified" since #55. The simulator delivers real key events, so
this looked closable from here. Half of it was.

**Verified against a live scratch session**: plain typing arrives (typed text
reached the shell), and Up recalls shell history. Both go through the same
`pressesBegan` path a Bluetooth keyboard would use.

**Not verifiable from here**: control combos. `app.typeKey("c", modifierFlags:
.control)` produced a literal `c` at the prompt, which looked exactly like a
real bug — ctrl+C leaving a stray character is precisely what a keyboard case
would suffer. Logging the raw UIPress settled it:

```
press keyCode=6 chars=c ignoring=c mods=0
view sent bytes 99
```

`mods=0`: XCUITest never delivered the control modifier, so the app received a
plain `c` and handled it correctly. **No bug — the harness was the bug.**

Worth recording because the first run of this experiment DID interrupt a
`sleep 300` with what looked like a real ^C, and I nearly wrote it up as
"hardware ctrl+C verified". Then the same gesture produced a stray character
twice running. Neither result was trustworthy; the byte-level log was.

Control combos stay on the device checklist, now with the reason attached
rather than just "unverified".

## The room was told the wrong background (iteration 103)

Claude Code picks its light or dark theme from the background the terminal
REPORTS — that is the mechanism hop2 fixed server-side in 2522c3e, and rooms
now answer colour probes with the viewer's real bg/fg, sent as `&bg=&fg=` on
attach.

This app sends them. It just stopped keeping them current: there are THREE
connect paths (attach, the automatic retry, reconnectIfNeeded) and only attach
set the client's theme. Toggle the terminal to light and every later
reconnect went on announcing the dark background — and hop has no runtime
message for colours, so the room never learned otherwise for the life of the
screen. On a phone, where reconnects are constant, that is most of the time.

Fixed where it can't be forgotten again: the theme pushes into the client on
every change rather than being read at each connect.

Demonstrated with a discriminator, after being wrong twice today about what
old code did. Identical probe — open a session, toggle the theme, reconnect —
against both builds, reading the background actually announced:

| | first connect | after toggle + reconnect |
|---|---|---|
| old | ffffff | ffffff |
| fixed | 0d1117 | ffffff |

The first attempt at this measurement was confounded: a previous run had left
the light theme persisted, so the app started light and the menu item the test
tapped no longer existed. The probe is label-agnostic now — it taps whichever
way round the toggle is, and asserts the announced colour CHANGES.

## Parked sessions (iteration 102)

hop2 gained park and archive yesterday — "hide without closing; sometimes kill
but keep resumable" — and this app knew nothing about either. A session parked
from the desk kept appearing in your pocket, which means it was not parked.

Took hop's own rules rather than inventing parallel ones, by reading
SessionSwitcher.tsx:

- The browsing list excludes parked; the FILTER still searches them. Parking
  is "not part of my working set right now", not "gone", and hiding a session
  whose name you just typed looks broken.
- Opening a parked session unparks it, best-effort, on every client rather
  than just this one.

One rule this app needs and the web has no equivalent for: **parked sessions
don't ring the phone.** Parking exists to cut noise, and a notification from
something deliberately hidden — which then isn't in the list you open to find
it — is the worst of both. The fleet summary carries a "N parked" count so
they are hidden but never silent.

Verified end to end against the daemon with a scratch session, the third part
from OUTSIDE the app: parked and absent from the list, found by typing its
name, and after opening it the daemon reported it unparked. Scratch session
deleted; fleet back to 19.

Not made a permanent UI test: it would have to park something on every run,
and mutating the fleet to test a filter is a bad trade. The rules themselves
are unit-tested.

## Bells could arrive twice, and two stores grew forever (iteration 101)

`HopNotifier` documents its contract as "one bell is one notification", and
kept the record of what it had already posted **in memory only**. A phone kills
apps constantly, and every relaunch re-notified every session still waiting —
bells already read and dismissed, arriving again. Now persisted, with the
decision itself pulled out as a pure `shouldNotify` beside `rebaselinedMarker`
(same restart case, seen from the other side) and unit-tested.

Found while verifying that: `seenBells` still held a marker for `scrolllock`,
the scratch session deleted an hour earlier. hop encourages killing and
recreating sessions, so that store grew for the life of the install. Both
stores now prune to the sessions that still exist; a name that comes back gets
a silent baseline, which is what a session this device has never seen should
get anyway.

Verified against the simulator's actual preferences file: the stale marker is
gone, 19 markers remain for 19 live sessions, and forcing an attention session
writes `notifiedBells = { Altair = 0 }` — the record the persisted dedupe then
reads on the next launch.

### A flake I couldn't name

One UI run failed and passed on retry; three further runs were clean, so call
it ~1 in 4. Its identity is unrecoverable because the call site piped
xcodebuild through grep and kept only the summary line. `make uitest` now
always writes the full log to `build-sim/uitest.log`. These tests drive a live
fleet, so the likeliest cause is a session being slow to attach — but that is
a hypothesis, not a finding, and the next occurrence will be nameable.

## Scrolling a session someone else is driving (iteration 100)

hop's server rejects every input from a non-controller and answers each one
with "Control is locked". Scrolling now sends one message per row of travel,
so a single flick on a locked session fired ~15 doomed messages and got ~15
rejections back — pinning that toast for the whole coast, for trying to READ.

Scrolling now sends nothing when someone else holds control, and says so once
per gesture. Local scrollback is unaffected: that path never touches the
socket, so history in a shell session still reads fine while locked.

Verified with a controlled experiment on a scratch session, since a guard that
blocks everything would look identical to a guard that works:

| | scroll sent | blocked |
|---|---|---|
| probe holds control | 0 | 15 |
| control released | 15 | 0 |

Same alt-screen pager, same flick, same count of travel — only the lock
differs. The scratch session was created for this and deleted afterwards
(fleet back to 19).

## Measured, then NOT built: capping the coast on Low Data (iteration 99)

Every wheel notch makes the remote app repaint, so momentum has an INBOUND
cost, and the app already drops previews entirely in Low Data Mode. The
obvious next step was to cap the coast there too.

Measured it first, against idle sessions with a control period (both controls
read 0 bytes over 3s, so these are clean):

| session   | bytes per notch |
|---|---|
| Polaris   | 86 |
| Supernova | 875 |

Worst case ~875 B/notch, and a hard flick is about 50 notches: **~44 KB**.
That is not a price worth degrading the core interaction for. Previews are a
nicety and Low Data drops them; reading output is what the app is FOR. No cap.

Recorded so the idea isn't re-litigated: the number that matters is 44 KB per
hard flick, worst case, uncompressed.

## Reconnect when the route changes (iteration 98)

A phone changes networks constantly, and the terminal only reconnected on two
signals: coming back to the foreground, or the manual menu item. Walk out of
wifi range onto 5G with the app open and the socket is dead, the backoff has
grown to 15 seconds, and the screen stays dead for all of it while the phone
has had a working route the whole time.

`isOnline` cannot report this — that transition leaves the path SATISFIED the
whole way, so nothing in the app ever learned that every open connection had
become dead weight. NWPathMonitor knows the route itself changed, so
NetworkConditions now publishes a generation that bumps only on a material
route change (satisfied / wifi / cellular / wired), and the terminal
reconnects on it under the same guard as the foreground case: only a CLOSED
socket, because every reconnect pulls a fresh snapshot on someone's cellular.

Verified as far as it can be from here: the monitor-to-view chain fires,
`route wifi (change 1)`, exactly once at launch and not repeatedly. The
transition that matters — wifi to cellular — needs a phone that moves, so it
is unverified until this is used away from the desk.

Also checked and found already correct, so it isn't re-checked: output
arriving while you're scrolled back does NOT yank the view to the live edge.
SwiftTerm's public scrollTo sets `terminal.userScrolling`, which is what its
scroll routine consults, and the Live button clears it.

## Correction: what the size logs actually showed (iteration 97)

The iteration-96 entry below claimed the log caught a 48-row grid being drawn
into a 23-row view for 1.7 seconds. **That reading was wrong.** Instrumenting
the snapshot showed `fitted 51x48, terminal 51x48` — the two MATCHED. The view
really did fit 48 rows at that moment, because the keyboard hadn't appeared
yet; the later "fit 51x23" is the keyboard taking half the screen, which is
correct behaviour, not a bug being fixed late.

What survives, and why the change stays:
- Adopting a peer's size still means drawing a grid that doesn't match this
  view, and SwiftTerm clips whatever falls outside its bounds. hop's web client
  refuses the same resize in auto-fit mode. That reasoning never depended on
  the log.
- SwiftTerm re-fits only when its BOUNDS change, so any size set from the
  network (the fast paint does this) survives until the keyboard happens to
  appear. The snapshot now restores the fitted size, which is a no-op in the
  common case — measured: the snapshot usually beats the fast paint entirely.

The mistake was reading a log line as evidence for a bug I had already decided
was there. The line said "we draw 51x48" and I read it as "we draw 48 rows in
a 23-row view" — it actually said the view was 48 rows tall.

## Adopting a peer's size hid claude's input box (iteration 96)

Following the previous fix upstream: why was the local terminal ever a
desktop's size? Because `active_size` was applied unconditionally. SwiftTerm
draws the grid it's given into the bounds it has, so a 50-row desktop size on
a phone drawing 23 rows puts the bottom 27 rows outside the view — and the
bottom is exactly where claude's input box is.

hop's web client refuses the same resize in auto-fit mode, and its comment
names the symptom it was written for: "mobile snapping to a desktop/PTY
80x24". This app is always auto-fit, so it now records the elected size and
logs the mismatch instead of adopting it.

**See iteration 97: the log evidence quoted in this entry was misread. The
change stands on the web client's lesson, not on that measurement.**

The cost is reflow — output written for 80 columns wraps in a 51-column grid —
and that is the better failure: wrapped is worse to READ, clipped means you
can't see it at all. It self-heals as soon as our attach claim wins.

Why this was never noticed: the attach claim usually DOES win (2.5s idle
window), so the sizes match and nothing looks wrong. It bites exactly when
someone is typing at a desk while you open the same session on your phone.

## Scroll speed was tied to the wrong row count (iteration 95)

hop runs ONE PTY at one size for everyone, and this app resizes its local
terminal to whatever size the room elected — often a desktop peer's, since the
election follows whoever typed last. The scroll math divided the view's height
by `terminal.rows` to get a cell height. When a 50-row desktop holds the size
and the phone is drawing 23 rows of that grid, that division is wrong by more
than 2x, and every row of finger travel counts as two: scrolling runs at double
speed for as long as the desktop holds the size.

Now divides by what the view actually DRAWS, which SwiftTerm already reports
through sizeChanged (the same number the attach claim is built from).

Reasoned from the code and pinned by a unit test rather than observed live:
reproducing it means having a peer actively type on a shared session while the
phone attaches, and the only sessions available to do that with are other
agents' real work.

## Who owns the screen, not what we happen to have (iteration 94)

The three-way scroll rule was branching on "do we have local scrollback yet",
which is not the question. hop's web client branches on ALT SCREEN, and the
difference shows at a bare shell prompt: a fresh session has no scrollback, so
our rule fired Page keys at a shell that never asked for them — and then
silently switched to scrolling our own buffer once enough output had piled up.
The same gesture on the same session doing two different things depending on
how long you'd been looking at it.

(Checked what that actually does: this machine's zsh has no binding for
ESC[5~, so it was inert HERE. That is a property of one machine's config, not
a defence of the rule.)

The decision is now a pure function of who owns the screen — `scrollSink` —
and alt-screen is tracked alongside the mouse flags, seeded from the snapshot
and followed live through 47/1047/1049. `RemoteMouseState` became
`RemoteModes` accordingly.

## The coast was wrong on the phone and right in the simulator (iteration 93)

The momentum written an hour ago decayed per FRAME. CADisplayLink runs at up
to 120Hz on a ProMotion phone — which is the phone this is for — and at 60Hz
in the simulator. So the glide would have coasted twice as fast for half as
long on the device, and every test and every simulator run would have kept
saying it was fine. Found by reading it back rather than by running it, which
is the only way this one could have been found: the hardware that shows it is
the hardware that can't be tested here.

Now decays per SECOND, taking each frame's real duration from the display
link (clamped, so a stalled frame doesn't spend a quarter second of travel at
once). The rate is UIScrollView's own 0.998-per-millisecond, since the ask was
for scrolling to feel like the rest of iOS and that is the number the rest of
iOS uses.

The test that matters runs the same flick at 60Hz and at 120Hz and asserts
both the distance and the duration match.

## A scroll is not a keystroke (iteration 92)

Followed what actually happens to a wheel event after `sendScroll`, and it was
going down the keystroke path — which does two things to it that are wrong:

- **It buffers through an outage.** A flick queues hundreds of wheel events;
  fifteen seconds later the connection returns and dumps them all at the
  agent, scrolling it somewhere you didn't ask for while you're reading
  something else. Keystrokes are worth replaying because you meant them. A
  scroll is about NOW.
- **It marks typing**, telling every other client watching the session that
  you're typing when you're only reading.

Both fixed by giving scrolling its own path: straight out, or dropped.

**Observed but NOT fixed, because it isn't ours to fix alone:** hop's server
bumps `lastInputAt` on any input message, wheel events included, and the size
election runs on typing recency. So scrolling on the phone makes it the most
recent "typist", and a desktop resizing its window in the next 60s gets
rejected (`RESIZE_CLAIM_IDLE_MS`). The web client sends wheel the same way, so
this is hop-wide, not an iOS bug — a server-side fix would be to exclude
sequences that are purely mouse reports from the election. Flagged for the
hop2 side rather than changed unilaterally.

## Stopping the coast (iteration 91)

Momentum created an interaction that didn't exist before: what a touch means
while the screen is still moving. On iOS the answer is settled — the first
touch stops it and does nothing else — and without that, the tap that stops a
coast also raises the keyboard, shrinking the screen you were reading.

Worth recording HOW this was got wrong, because the assumption was reasonable
and false. The brake was first written in `touchesBegan`, setting a flag the
gesture delegate would read. Gesture recognizers are asked FIRST: the log
shows `shouldBegin UITapGestureRecognizer braking=false` at the same
millisecond the flag was being set, so the tap sailed through — and the flag,
now stale, swallowed an ordinary tap 1.5 seconds later. Both halves of that
were only visible because the test asserted the *next* tap still works.

The decision now lives in `gestureRecognizerShouldBegin`, where it's asked at
the right moment and needs no state at all.

## Momentum, and the scroll rework under it (iteration 90)

Jian, after confirming scrolling works: "will feel more natural if it has
momentum like most things in ios". Right — and momentum had been deliberately
withheld from agent sessions on the theory that flinging wheel events at an
app is spam. hop's own web client disproves that: it coasts alt-screen wheel
apps, and per-line wheel events are cheap.

Two changes, both learned by reading the web client rather than inventing:

1. **The flags live beside the terminal, not inside it.** The wheel path went
   through SwiftTerm's encoder, which reads OUR terminal's mouse state — so it
   only worked by feeding ?1000h/?1006h into the local terminal, changing what
   the terminal does in order to record a fact about the remote app. It also
   couldn't check SGR at all, because SwiftTerm keeps the encoding private.
   Now seeded from the snapshot and kept current by watching the stream.

2. **One debt accumulator, in points, for all three sinks.** Finger travel and
   momentum both push into it; one apply step spends it into wheel events,
   page keys, or our own viewport. Coasting works everywhere as a consequence,
   and slow drags stopped rounding to zero rows per frame.

The fallback for apps that don't take wheel is now Page keys, not arrows.
Arrows at a claude prompt recall previous PROMPTS — a scroll gesture that
rewrites what you were typing is worse than one that does nothing.

Verified by flicking a live agent session under XCUITest: 27 batches of wheel
events over 900ms, intervals stretching 17ms → 183ms as it decays. The finger
is gone for most of that.

**Not on the phone yet** — install has been failing on the lock screen since
this work started (`make install`, 15 attempts each time).

## Proving claude actually scrolls (iteration 89)

Before trusting the wheel fix, tested it against the live daemon with a
throwaway WebSocket client (wheel events scroll a view and inject no text, so
this is safe against a real agent session).

First run said **claude ignores wheel events** — which would have killed the
approach. It was wrong twice over: the session was showing a modal ("Enter to
confirm · Esc to cancel"), which ignores scrolling, and the first attempt used
THIS session as the subject, whose screen changes constantly because I'm
working in it.

Redone with a control period on an idle session at a normal prompt:

```
Polaris: changed on its own (control): false
Polaris: changed after 8 wheel-ups:   true
```

**Claude scrolls on wheel events.** Also measured, read-only, across the fleet:
every claude session is `alt=true mouse=true sgr=true`; the one shell session is
`alt=false mouse=false`. So the three-way scroll behaviour is exactly right, and
each branch has a real session that exercises it.

The lesson is the same one from the gzip measurement two days' work ago: an
experiment without a control is not a measurement. Both times the uncontrolled
version pointed the wrong way, and both times it pointed toward MORE work
(optimise polling; abandon wheel events).

## Why scrolling did nothing on agent sessions (iteration 88)

Jian: "still cannot scroll, number one issue." It was not the gesture — that
worked from the day it was added. Measured on a live session:
**`altScreen=true, scrollback reachable 23 lines`**, exactly the screen height.
Claude runs in the ALTERNATE screen buffer, which has no scrollback by design,
so a gesture that moves a local viewport had nothing to move. Every session in
this fleet is claude, so it looked entirely broken.

Scrolling means three different things depending on who owns the screen.
SwiftTerm's macOS view encodes all three for its scroll wheel; the iOS view has
no equivalent, and only the last was implemented here:

1. **mouse reporting on** (claude) → send WHEEL events; the app scrolls itself
2. **no scrollback, no mouse** (a pager) → arrow keys
3. **otherwise** → move our viewport, with momentum

Verified by driving a real drag through XCUITest and reading the log:
`scroll back 1 via wheel`, one notch per row of drag.

That exposed a second bug immediately: #37 deliberately did NOT restore mouse
reporting after the snapshot reset, so on a fresh connection `mouseMode` could
be off and the code would fall back to ARROWS — which claude reads as "recall
the previous prompt", not "scroll". Mouse mode is now seeded from the snapshot
flags. It does not bring back taps-as-clicks: SwiftTerm's own tap and pan
handlers remain disabled via `allowMouseReporting`, and only our scroll code
reads the mode.

A wheel event is also not a click, so #55's fix stands.

## What the app actually costs on cellular — and a measurement I got wrong

Measured against the live daemon:

| | raw | **on the wire** | foreground rate |
|---|---|---|---|
| session list | 9.9 KB (19 sessions) | **1.7 KB** (gzip) | 5s wifi / 12s cellular |
| one preview | 1.2 KB | ~0.5 KB | ×6, 9s / 25s |
| opening a session | — | **334 KB** | per open |

**≈0.6 MB/hour with the app open on cellular** — not the 4 MB/hour I first
concluded and acted on.

The mistake is the useful part: `curl` doesn't send `Accept-Encoding` unless
asked, so the first measurement was of an uncompressed response nobody
receives. URLSession requests gzip by default, and the daemon serves it — 9861
bytes becomes 1729. I was wrong by 6×, in the direction that makes optimisation
look worthwhile.

Acting on it, I had already slowed the list poll to a third whenever a terminal
was open. That trade — delaying "another agent needs you", which is the only
reason this poll exists — bought roughly nothing, so it is **reverted**. A
measurement taken with the wrong client is worse than none: it's confident.

## Swipe to reply, and a lesson about discriminating tests (iteration 83)

Swiping a session from the leading edge now offers **Reply** — the in-app twin
of the lock-screen reply, sharing its send path, so a rejection or dead socket
is reported rather than vanishing, and a success marks the session seen.

Covered by a UI test that opens the compose field and CANCELS. It deliberately
never sends: input to a live agent session could approve something, and no test
is worth that.

Getting there took three runs and the middle one is the useful lesson. When the
swipe found nothing, the question was "harness or product?" — so I added a
discriminator that swiped for the long-standing Kill/Rename actions. It
reported false, which looked like "the harness can't see swipe actions"… except
I'd swiped a staticText, which isn't the row. Swiping the CELL made the
discriminator say true, proving the harness was fine — and then the leading
swipe still failed, which turned out to be my test leaving the row already
swiped open from the discriminator itself.

A discriminating test that shares the flaw it's meant to rule out is worse than
no discriminator: it produced a confident wrong answer ("harness limitation")
that would have shipped an unverified feature.

## Reply to an agent from the lock screen (iteration 82)

The most phone-shaped thing hop can do, and a browser tab cannot do it at all:
an agent asks "proceed?", the notification carries the question (#81), and you
answer it without opening the app.

The bell notification now carries a Reply action. hop accepts input only over
the WebSocket — there is no HTTP input endpoint — so a reply opens a throwaway
connection, sends the line, and closes. It asks for `replay=1`, since a
fire-and-forget send has no use for the 334 KB join snapshot.

Failure is reported, not swallowed: if the socket never opens, times out (12s,
so a sleeping tunnel can't hang a background launch), or the input is REJECTED
because another client holds control, a follow-up notification says the reply
didn't land. Believing you answered when you didn't is the worst outcome
available here.

**NOT verified end to end, deliberately.** Testing it means sending real input
to a real session, and a stray newline in an agent session could approve
something. On the device checklist with a safety note: **try it first on a
shell session, not an agent.**

## A notification that says what the agent asked (iteration 81)

The body was the session's TAGLINE — a description of what a session is for,
which never changes, and so never answers the only question a bell raises:
what does it want? "Do you want me to proceed?" is worth waking a phone for;
"Polish mobile client" is not.

The body is now the session's last meaningful output line, with the tagline
demoted to the subtitle so you still get which session and what it's for
without crowding the part you read. Cached previews are used when available,
and fetched otherwise — a session that just rang is often NOT among the handful
whose previews are polled, which is exactly when the content matters most.

Also corrected a stale comment: time-sensitive delivery was recorded as
permanently stripped, which was true under the wildcard App ID. The App ID is
explicit now, so it's a one-line entitlement away if Focus breakthrough is
wanted.

Empty states verified on screen for the first time while here: "No matches"
renders correctly, and content search still answers when the name filter finds
nothing. (First attempt failed amusingly — the search term appeared in my own
command, which lands in this session's scrollback and matched.)

## The headline feature shipped off, three taps deep (iteration 80)

Bell notifications are the reason to have this on a phone instead of a browser
tab — and they defaulted to OFF, behind `⋯ → Bell notifications`. Anyone who
didn't already know they existed would never find them, which for the first
TestFlight install means the app's whole point is invisible.

It now asks once, ever, and asks IN CONTEXT: after the session list has actually
loaded, so the offer arrives with your sessions behind it rather than against an
empty screen at launch. `@AppStorage` remembers the asking, not the answer, so
declining is respected permanently and there's no nagging. Skipped entirely if
notifications are already on.

Verified from a clean install (uninstalled the simulator app first, since
first-run is another state that can't be reached on demand once it's past).

## Every reconnect cost two connections (iteration 79)

Reviewing HayClient's socket lifecycle: `close()` cancelled the task but left
its pending `receive` to fire with a failure. The coordinator can't tell that
apart from a real drop, so it set the status to closed and **scheduled a
retry** — while a new connection was already in flight.

Measured before fixing, one "Reconnect" tap: snapshots at **13:54:16.99**
(open), **:20.25** (the tap), **:21.30** — a third connection exactly 1s later,
matching the backoff's first delay. Each one costs another 334 KB and another
attach claim, and the claim reflows the PTY for **everyone** attached, so a
reconnect on the phone made a desk terminal redraw twice.

Sockets now carry a generation, bumped on close, and results from a retired one
are ignored. Re-measured: **3 → 2** connections, which is open plus the
requested reconnect. Also affects the automatic paths — waking the phone and
foregrounding both go through the same close/connect.

## State that outlives what it describes — audit (iteration 78)

#77's bug lived in state that survived the thing it described, so I checked the
rest. `previews` are pruned to live sessions, `QuickActions` replaces its
signature each publish, the keychain password is per-server and cleared on sign
out, cookies are dropped on rejection and sign-out, `notified` and `seenBells`
now rebaseline. Settings (font size, theme, grouping, server) are meant to
persist.

One deliberate non-fix: `seenBells` grows forever, since entries for dead
sessions are never removed. Pruning to live sessions looks tidy but is worse —
a session that's temporarily absent (a parked one, or a hiccup returning a short
list) would lose its marker and come back silently, swallowing bells rung while
it was away. The growth is a dictionary of name→int; correctness beats tidiness.

Also brought the README's dev-flag documentation up to date: three flags
(`COMPACT`, `ATTENTION`, `GONE`) had gone undocumented, and the `-hop-ui-testing`
argument wasn't mentioned at all.

## A recreated session could never ring (iteration 77)

Reviewing the collab flow (which turned out sound — hop's `removeClient`
releases control on disconnect, so leaving while holding it can't strand your
desktop locked) led to a real bug next door.

Seen-bell markers were seeded only for sessions this device had **never** seen.
Kill a session and recreate it under the same name — which hop encourages —
and its `bellSeq` restarts at 0 while the stored marker holds the old value.
`attention` is `bellSeq > marker`, so the new session would stay **silent until
it rang more times than its predecessor ever did**. A session named `Orion`
that had rung 50 times would need 51 bells before the phone said anything.

A bellSeq that goes backwards can only mean a new session wearing an old name,
so the marker is now rebaselined when that happens — in the list AND in the
notification dedupe, which had the identical flaw. Pure function, four cases
pinned by a test. 31 tests.

## Two more counts that disagreed with the list (iteration 76)

Audited every place the app shows a number, using the lesson from #75 —
displays get written against the data nearest to hand rather than the question
being asked. Two more:

- The Account sheet's **"Sessions"** row and Copy Diagnostics both counted
  `sessions.count`, which INCLUDES port forwards, while the list excludes them.
  A sheet saying 20 while the list shows 19 is worse than no number, because it
  looks like something is missing. Both now use `terminalSessions` — what the
  app means by "a session" everywhere the user can see.
- `alertable` counted attention on ports too. A forwarded port has no terminal
  to open and cannot ring, so a badge counting one would be uncleanable.
  Excluded, with a test.

Clean: the badge, quick actions and presence counts were already asking the
right question.

## The summary agreed with whatever you'd filtered to (iteration 75)

The fleet summary counted attention across the VISIBLE rows. So filtering to
one project — or switching scope to "You" while an agent session was waiting —
made it report **"nothing waiting on you"** while something was. Technically
true of what was on screen, false about the fleet, and wrong in the direction
that matters: the entire job of this line is to answer "is anything waiting?"

Attention is now counted across the whole fleet, the session count says
"1 of 19" when narrowed, and it names what's hidden: **"1 of 19 · 1 wants you
(1 not shown here)"**. Verified on screen with a filter that deliberately
excludes the waiting session.

Same species as the offline banner in #43 and the stale error in #32: the app
knowing something and showing something narrower.

## Where UI testing stops being worth it (iteration 74)

Tried covering find-in-scrollback and "Open link…". Both failed, and the useful
part is WHY: their feedback is a 2-second toast, and for links a confirmation
dialog in a separate presentation layer. XCUITest sees neither reliably — the
toast can clear before an assertion starts, and the dialog title isn't a
queryable staticText. In both runs the wiring was demonstrably fine: the find
bar opened and accepted typing.

Reverted rather than shipped. A red test against working code is worse than no
test — it trains you to ignore the suite, which is the one thing that makes the
other seven worth having. Both features stay on the device checklist, and the
logic beneath them (`findMatchRow`, `extractLinks`) is already unit-tested;
what's unverified is only the last inch of UI wiring.

That's now the boundary of this harness, drawn from evidence rather than guessed:
- **Automatable**: navigation, rotation, sticky modifiers, sign-out, search
  round trips, session switching, keyboard focus.
- **Not**: anything whose only signal is a transient toast, a system dialog, a
  SpringBoard surface (quick actions, badge), or a haptic.

## Two more flows covered; one refactor abandoned (iteration 73)

Added, both read-only against the live daemon so they're safe to run:
- **`testSearchFindsSessionsByTheirOutput`** — types a term known to be in the
  fleet and asserts the "Found in output" section appears, which proves the
  server round trip rather than just the UI.
- **`testSwitchSessionFromTheTitleMenu`** — switching from the terminal title
  goes through the same `requestedSession` path that cold-launch quick actions
  use, the one that silently did nothing until #51.

Suite: 7 tests, 62s, one honest skip.

**Abandoned:** replacing the hardcoded session names with "tap the first row".
The intent was good — names break confusingly the day a session is renamed —
but XCUITest's element model for a SwiftUI List didn't cooperate with either an
index or a label predicate, and two attempts turned a green suite red. Reverted
and wrote the coupling down instead: if those sessions vanish the failure names
them, and the fix is one string. Cheaper than the fragility I was adding to
remove it.

## The UI suite went from unrunnable to 48 seconds (iteration 72)

Individual UI tests were fast but the SUITE exceeded ten minutes, so it could
never run in one go. Profiling the slow one showed where every second went:
**"App animations complete notification not received"** — a 60-second wait
before *each* interaction, because the app never becomes idle. The cause is the
blinking caret: a permanent animation, so XCUITest concludes the app is
perpetually mid-animation.

Under `-hop-ui-testing` the caret is steady (the app keeps its blink). The tap
test went **190s → 9s**, and the whole suite now runs in **48 seconds**:

| test | covers |
|---|---|
| `testCtrlArmsAndDisarms` | sticky modifiers, never pressed before #70 |
| `testLandscapeHidesChromeButKeepsTheKeyBar` | real rotation, not the dev-flag proxy |
| `testSignOutReturnsToLoginAndStaysThere` | destructive flow + the #20 race, with a 6s wait to prove a refresh doesn't put you back in |
| `testTapRaisesTheKeyboard` | the tap that did nothing on every agent session |
| `testDragScrollsAndLiveButtonReturns` | skips honestly when the shell has no scrollback |

Sign-out was the third checklist item to turn out automatable after I'd written
it off. It's safe to run: it clears only the simulator's cookie, which the dev
bootstrap re-seeds next launch.

## Landscape verified for real (iteration 71)

XCUIDevice can rotate the simulator, which I hadn't used — so landscape had only
ever been checked through `HOP_DEV_COMPACT=1`, a proxy that forces the compact
layout in portrait. `testLandscapeHidesChromeButKeepsTheKeyBar` now does the
actual thing: asserts the nav bar is present in portrait, rotates to landscape,
waits for it to disappear, and confirms the key bar survives — because a
chrome-free terminal that also lost `esc` would be a downgrade.

That closes one of the three device-checklist items I'd written off as
"needs your hands". Remaining there: pinch zoom, and long-press selection
(whose menu belongs to another process and can't be queried).

## Sticky modifiers: announced, and finally pressed (iteration 70)

Continuing the "unexecuted code is where the bugs are" pass. ctrl and alt are
the key bar's least visible feature and its most load-bearing — ctrl+something
is how you interrupt, clear or search a terminal — and nothing had ever pressed
them. Their armed state was communicated only by a background tint, which is
invisible to VoiceOver AND to any test.

They now set `accessibilityValue = "armed"`, which fixes both at once: a screen
reader says it, and a UI test can assert it. `testCtrlArmsAndDisarms` passes —
sticky ctrl arms on one tap and disarms on a second.

Harness note for next time: XCUITest reports a nil `accessibilityValue` as `""`,
not nil, so `XCTAssertNil` fails against working code. The first run failed on
exactly that while the middle assertion — the one that mattered — passed.

## Push registered only once, ever (iteration 69)

The registration added two iterations ago fired from `setEnabled` — the moment
you toggle notifications on — and nowhere else. So the device token was
obtained exactly once and never refreshed. APNs tokens change on reinstall,
restore-from-backup and some iOS updates, and Apple's guidance is to register
on EVERY launch and refresh the server's copy each time. As written, push would
have worked once and then silently stopped, with a stale token nobody could see
was stale — the same shape as every other failure this project has hit.
Registration now runs at launch whenever notifications are granted.

Also gated the two dev flags that fake app state (`HOP_DEV_ATTENTION` invents
attention, `HOP_DEV_GONE` invents an ended session) behind `#if DEBUG`, joining
the dev cookie. Flags that only pick a screen or a filter are inert and stay.

## The app icon would have failed TestFlight (iteration 68)

Chasing Release-build warnings before the first upload found a blocker, not a
nit: **"A 1024x1024 app store icon is required"** and **"A 60x60@2x app icon is
required"**. The icon set had the right 1024 image but its `Contents.json`
carried `"scale": "1x"`, which makes Xcode read it as a legacy multi-size entry
with everything missing, rather than the modern single-size icon. Dropping the
key clears both. App Store validation rejects builds for exactly this, so it
would have surfaced as a failed upload after everything else was ready.

Also cleared the three code warnings, one of which was real:
- `fastPaint` captured `self` as a var crossing into concurrent code — the same
  shape as the race in #49. Now `Task { @MainActor [weak self] }`, so the
  network await still suspends off-main and the body resumes on the actor,
  with no nested `MainActor.run`.
- The quick-action scene delegate used the ASYNC UIKit variant, which must send
  a non-Sendable `UIApplicationShortcutItem` across an actor boundary. The
  completion-handler form is `@MainActor` and needs no crossing — UIKit calls
  it on the main thread anyway, so the annotation is just the truth.
- An ignored `resignFirstResponder()` result.

Release now builds with **zero warnings** from our own code and assets.

## Push environment per configuration (iteration 67)

`aps-environment` was hardcoded to `development`. A TestFlight build carrying
that registers against SANDBOX APNs, so production pushes never arrive — a
failure that looks exactly like "push doesn't work" with nothing in the logs.
It is now `$(APS_ENVIRONMENT)`: development in Debug, **production in Release**,
verified via `-showBuildSettings` for both configurations.

Honest limit: the archive itself still shows `development`, because Xcode
archives with development signing and re-signs at export — where it is expected
to rewrite the value. That last step needs the App Store Connect app record, so
it is NOT yet verified end to end. Worth checking on the first TestFlight build
(`codesign -d --entitlements -` on the exported .ipa) before concluding push
works or doesn't.

## One reshape per open, and saying when it happens (iteration 66)

Answering Jian's question about independent terminal sizes turned up a real
defect in our own behaviour.

**Opening a session sent TWO PTY resizes.** The attach claim went out at the
pre-keyboard height (51x48), then the keyboard appeared and took half the
screen, triggering a second resize (51x23). One PTY means one size, so a desk
terminal reflowed TWICE because someone glanced at their phone. Resizes are now
held until the layout settles (~400ms) and exactly one claim goes out, at the
size we actually keep. Verified: `attach claim 51x23`, where it used to read
`51x48` followed by a correction.

**And the phone now says when it reshapes someone else's session** — but only
when the change is real (>8 columns different from what the room was using when
we joined, which `hello` carries). Opening a session already at phone width
says nothing.

On the underlying question: independent sizes are impossible, not merely
unimplemented. One session is one PTY with a single TIOCSWINSZ, and a TUI draws
to that grid with absolute positioning — two sizes means one client gets
garbage, not a slightly-wrong view. tmux hits the same wall and solves it the
same way (a size policy: latest/smallest/largest; hop's typing-recency election
is "latest"). Independent VIEWS are possible and hop's web client has them
(`fit` claims, `full` keeps the shared size and pans), but on a phone a
120-column grid is ~3pt per column, so panning is the only way to read it.
Notably, NOT claiming is worse for agent sessions: claude would keep drawing
for 160 columns into our 51-column grid, which is scrambled rather than wide.
Claiming is the precondition for legibility, not a preference.

## Glanceable count + a real "session ended" state (iteration 65)

- **Fleet summary.** With nineteen sessions the header said nothing useful.
  It now reads "19 sessions · 1 wants you", amber when something is waiting and
  "nothing waiting on you" when not — the zero case is an answer, not silence.
- **Session ended.** A session that ends, or a room the server no longer has,
  used to leave a red line buried in the scrollback — easy to miss when you've
  just tapped in expecting a live terminal. There's now a card: what happened,
  why, and a way back. The scrollback stays readable behind it, because the
  last thing the session printed is usually why you opened it.
  `HOP_DEV_GONE=1` renders the state, which is otherwise unreachable on demand.

## APNs entitlement is LIVE (iteration 64)

`aps-environment => development` is now in the signed app, verified with
`codesign -d --entitlements`. #16 and #26 both recorded this as silently
stripped; it took three things, and the last was self-inflicted:

1. An **explicit App ID with Push enabled** (#63). A wildcard App ID cannot
   carry the entitlement — Apple simply drops it.
2. **Getting Xcode to stop using the cached wildcard profile.** It matched
   `io.zhoulab.hop.spike` and won every time. Moving it aside (backed up, and
   lightscope's own explicit profile untouched) made Xcode create
   `iOS Team Provisioning Profile: io.zhoulab.hop.spike`, which carries
   `aps-environment`.
3. **XcodeGen overwrites `HopSpike.entitlements` with an empty dict** unless
   the contents are declared in `project.yml` under `entitlements: properties:`.
   Exactly the trap #45 hit with Info.plist — a generated file edited by hand,
   silently discarded, build green. Second time; now commented in project.yml.

Client half of push is implemented: `PushRegistry` registers for remote
notifications once notification permission is granted, keeps the device token,
and surfaces it in Copy Diagnostics (first 16 chars) so it can be read off a
phone. Delivering an actual push still needs the daemon side — an endpoint to
register tokens against and a send-on-bell path — which are hop2 changes.

## TestFlight: everything done except one web form (iteration 63)

Asked to push to TestFlight. Got most of the way; the last step is Apple's to
refuse, not mine.

**Done here:**
- Found the credentials: an **Apple Distribution certificate** already exists,
  and an App Store Connect API key sits at
  `~/.appstoreconnect/private_keys/AuthKey_CCFL4WD4V4.p8`. The issuer ID was in
  the **lightscope** repo (Jian's pointer) — `254072af-…`. Verified working
  against the live API.
- Diagnosed why plain `-allowProvisioningUpdates` fails: **"No Accounts"** —
  Xcode has no Apple ID signed in, so it can't create a distribution profile.
  Development builds only work because the wildcard profile is cached on disk.
  The API key does that job instead, and `make testflight ISSUER=<uuid>` now
  passes it to xcodebuild for both profile creation and upload.
- **Registered `io.zhoulab.hop.spike` as an explicit App ID** (ID `JN2AVFVXZA`)
  — it wasn't registered at all, which is why every build fell back to the
  wildcard profile.
- **Enabled Push Notifications on it.** That is the exact blocker #26 found for
  APNs: Apple does not allow Push on a wildcard App ID. Apple's side is now
  ready; what remains for push is the daemon endpoint and an APNs key.

**What only Jian can do:** create the app record in App Store Connect. The API
refuses it outright — `The resource 'apps' does not allow 'CREATE'` — so it is
the web UI or nothing: App Store Connect → Apps → **+** → New App, platform
iOS, bundle ID `io.zhoulab.hop.spike` (now in the dropdown), any SKU, and a
name of your choosing. Then `make testflight ISSUER=254072af-7f14-4065-acd8-d09fe4924553`
runs the whole loop, and the build installs over 5G with no cable.

## Attention had to be findable (iteration 62)

The one state this app exists to surface was the quietest thing on screen: a
green dot ringed in red, plus a small bell. Scanning nineteen rows, that is
easy to miss — and if you miss it, the app has failed at its only job.

- Attention now OWNS the status dot: filled amber with a soft halo, instead of
  a red ring around a green dot that was trying to say two things at once.
  Liveness keeps plain green; the redundant bell icon is gone.
- The whole row carries a faint amber wash, so it is findable while scrolling
  rather than only when you stop and look.
- Amber, not red: red in a list of agent sessions reads as "something failed",
  and a session wanting you usually hasn't.

`listRowBackground` has to go on the element the List owns, not inside the row
— applied nested it silently did nothing, which cost a screenshot to notice.

Added `HOP_DEV_ATTENTION=1` (`make sim ATTN=1`) to force the state. Reviewing
the design of the app's central state should not require waiting for an agent
to ring.

### Same bug, other strip (iteration 61)

The keyboard-down case had it too: the terminal ignored the bottom safe area,
so autofit counted rows under the HOME INDICATOR. Measured before/after by
dismissing the keyboard from the UI test and reading the layout log:
**724pt now, ~775pt before** — about two rows that were sitting behind a system
control. Keyboard-up is unchanged at 358pt/23 rows, since the keyboard covers
that strip anyway.

The pattern in both: a terminal autofits to its FRAME, so anything overlapping
the frame silently steals the bottom rows — which are the live end of the
session. Worth checking whenever chrome is added near the bottom edge.

## Delivering over cellular (iteration 60)

The signing profile says `TimeToLive = 365` (expires 2027-07-25) — a PAID
Developer Program membership, not a free personal team, which would be 7 days.
That matters: builds don't expire weekly, and both cellular delivery paths are
available.

- **Right now, no setup**: turn on Personal Hotspot and join the Mac to it. The
  phone and Mac are then on one network and `make install` works over 5G.
- **Properly**: TestFlight. `make archive` is verified working; `make
  testflight` exports and uploads. Needs three one-time account actions that
  are outward-facing and were NOT done from here — an explicit App ID, an App
  Store Connect record, and a distribution certificate. Internal testers get
  builds with no review. This is also exactly the explicit App ID that #26
  found APNs blocked on, so it unblocks push at the same time.
- Ad-hoc OTA from hop.zhoulab.io would also work over 5G, but it needs the same
  certificate plus hosting a manifest, for less than TestFlight gives.

## Key bar conflict + one surface palette (iteration 59)

**A conflict I introduced and caught before Jian did.** #54 put PgUp/PgDn on
long-presses of ↑/↓ — but those keys already had hold-to-repeat from #14. The
long press fires at 0.35s, the repeat at 0.42s, so holding ↓ to walk shell
history sent a page-down and never repeated: #14's whole point, undone by #54.
Long-press alternates now live ONLY on keys that don't repeat, which means tab
(⇧tab) and nothing else. PgUp/PgDn are visible keys again, and widths are tuned
so the nine you reach for constantly — esc…→ — fit without scrolling, with
paging, paste and dismiss just past the edge.

**Surface palette.** The chrome was ad-hoc greys — `white: 0.07` nav bar,
`white: 0.11` key bar, `white: 0.22` key caps — sitting against a terminal at
#0d1117. Neutral darks next to a blue-tinted one read as three unrelated
materials. Now one family derived from the terminal's own background: surface
#0d1117, raised #161b22 (nav bar, key bar, find bar), keys #272e38, armed
modifier #9d7bf5. Defined once in `Color`/`UIColor` extensions rather than
inline per call site, so the next surface can't drift.

## Touch was breaking THREE interactions, not one (iteration 58)

Writing a UI test for selection turned up the full extent of the mouse-reporting
problem. SwiftTerm gates these three behind `allowMouseReporting && mouseMode
.sendButtonPress()`, and claude turns mouse mode on:

| Gesture | Before #55 (agent sessions) | Now |
|---|---|---|
| Drag | click sent to the app; viewport never moved | scrolls |
| Tap | click sent; keyboard stayed down | focuses, raises keyboard |
| Double-tap | click sent; nothing selected | selects a word, offers Copy |

So on every claude session — which is what this app is FOR — touch did nothing
locally and quietly poked the agent instead. One wrong assumption (touch is a
mouse), three dead interactions.

Also learned: `enableSelectionPanGesture()` adds the selection pan LAZILY, when
a selection starts. #55 disabled the pans that existed at setup, so
drag-to-extend was never actually traded away — the earlier note overstated the
cost.

Test-harness limits worth recording, since three runs were spent finding them:
- The edit menu ("Copy") is presented by another process and never enters this
  app's accessibility hierarchy, so it cannot be asserted from here. Selection
  stays a device-checklist item.
- SwiftTerm's long press does NOT select — it only opens a context menu.
  Double-tap is what selects. Asserting the wrong gesture made working code
  look broken.
- UI tests run ~2-4 min each, so they exceed a single 10-minute command when run
  as a suite; use `-only-testing:` per test.

## Scroll momentum + a UI test target (iteration 57)

**Momentum.** The scroll was 1:1 with no inertia, so reaching anything more
than a screen back meant swiping over and over. Every scroll view on the
platform coasts; one that doesn't reads as broken rather than minimal. A
CADisplayLink decays velocity at 0.94/frame (≈ UIScrollView's feel, about a
second of glide), stops at the top, and is torn down in both `deinit` and
`didMoveToWindow(nil)` — #19's leaked-timer lesson applied up front instead of
after the fact.

**`make uitest`.** Every interaction defect in this app — no touch scrolling,
taps not raising the keyboard, drags scrolling out from under a selection — was
invisible to unit tests AND to screenshots, because none of them involve a
finger. XCUITest drives real gestures at the real app, which is the only
automated way to catch that class here. Auth comes from the daemon token via
`TEST_RUNNER_HOP_DEV_COOKIE`.

First run earned it: **tap-to-raise-the-keyboard passes**, which is real
regression cover for #56's silent breakage.

Two things learned writing it:
- The scroll test failed at first because it opened a CLAUDE session. TUI apps
  have no scrollback (alt buffer), so there was nothing to scroll to — the test
  was wrong, not the code. It targets a shell session now, and SKIPS rather
  than fails when that shell has been idle: a red suite meaning "the session
  was quiet" teaches you to ignore red.
- It's slow (~4 min per test, dominated by launch and session load), so it is a
  separate target from `make test` and meant for interaction changes, not
  every commit.

## Tap-to-refocus was broken on every agent session (iteration 56)

Checking whether #55's `allowMouseReporting = false` had broken tap-to-focus
turned up the opposite: it FIXED a bug that had been there all along.

SwiftTerm's tap handler is an if/else. The mouse branch — taken whenever the
app has mouse tracking on, which claude does — sends a click and returns. Only
the else branch calls `becomeFirstResponder()`. So on any claude session:
dismiss the keyboard with ⌄, tap the terminal to get it back, and **nothing
happened** — the tap went to claude as a stray click instead. The keyboard was
only ever raised by opening the session in the first place.

Now that taps and drags stay local, the else branch always runs: a tap focuses
the terminal and raises the keyboard, and claude stops receiving phantom
clicks. Same root cause as the scroll problem — SwiftTerm forwards touch to the
app as mouse input, which is right for a desktop terminal and wrong for the
only pointing device a phone has.

## Cold-launch navigation was broken (iteration 51)

Applying #50's lesson — *the thing new code hooks into may have several entry
points* — to navigation, and it found a real one.

Both headline entry points route through `.onChange`: quick actions set
`model.requestedSession`, notification taps set `notifier.pendingOpen`.
**`onChange` does not fire for a value that was already there.** A cold-launch
quick action sets its value during scene connect, and a notification tapped
with the app closed sets it as the delegate comes up — both long before
`SessionsView` exists. So: long-press the icon with the app closed, or tap a
bell notification with the app closed, and **nothing happened**. The two
features most worth having on a phone, silently inert on the path that matters
most, since the whole point is reaching a session without opening the app first.

Pending requests are now consumed when the list appears, waiting for the
session to be known so a dead route is dropped rather than pushed.

Verified by rewiring `HOP_DEV_OPEN` to set `requestedSession` in `App.init()`,
before any view exists — so `make sim OPEN=X` now exercises the real
cold-launch path rather than a parallel one. Confirmed on screen: the app opens
straight into the session.

## Task-safety audit (iteration 50)

Swept every `Task {` after #49 found one racing. Result: the rest are fine —
those inside SwiftUI views and inside `@MainActor` types inherit the actor, and
the two in the terminal coordinator (fast paint, reconnect backoff) both do
their UIKit work inside `await MainActor.run`. Only #33's diagnostic was wrong.

The sweep found a different bug though: **three call sites connect the socket,
and only two fast-painted.** The missing one was the automatic backoff retry —
a tunnel blip, or a phone waking from sleep — which is both the MOST common
reconnect and the case where you're already staring at a dead terminal, so the
slowest path was the one that needed it most. #41 wired the two explicit paths
and missed the automatic one. All three now reset `snapshotLanded` and paint.

## Crash-safety + concurrency audit (iteration 49)

Force-unwrap sweep: one `try!` (a literal regex in Links.swift, exercised by
five tests) and one `Int.max / 2` passed to SwiftTerm's `scrollTo`, which clamps
with `min(row, maxScrollback)` before any arithmetic. Every `removeLast`,
`removeFirst` and `dropFirst` is guarded by the check immediately above it, and
`prefix`/`suffix` clamp by definition. No unchecked indexing anywhere. Clean.

Then built with `SWIFT_STRICT_CONCURRENCY=complete`, which found **a real race
I introduced in #33**: the scrollback-depth diagnostic ran in a bare `Task`, so
it walked SwiftTerm's buffer — plain arrays, main-actor-isolated — from a
background thread while the feed was writing into it. A logging line quietly
reading a live data structure from the wrong thread; the kind of thing that
crashes on a device under load and never in a simulator. Now `@MainActor`.

**67 warnings remain and are deliberately left.** Nearly all are one pattern:
HayClient's event callback is nonisolated while calling main-actor UIKit, having
been dispatched through `DispatchQueue.main.async`. That is correct at runtime
but unprovable to the compiler. The obvious "fix" — switching to
`Task { @MainActor in }` — would **break FIFO ordering of terminal output**,
because separate Tasks carry no ordering guarantee, and out-of-order output
corrupts the display. The right fix is `MainActor.assumeIsolated` at each
dispatch site plus a `@MainActor` callback type; it buys Swift 6 readiness and
nothing at runtime, so it's debt recorded rather than churn taken.

# Reference — how it got here

## Spike test script (once installed)
1. On Mac: `node ~/Code/hop-ios/tools/lan-bridge.mjs` → note the ws:// URL.
2. On iPhone: HopSpike → paste URL, session e.g. `Solstice` → Attach.
3. Judge: keyboard feel (real keys, autocorrect/dictation, key repeat),
   scroll physics, latency vs the web client. That verdict gates v1.

## Simulator review loop (Orion can SEE the UI now)
`xcodebuild -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build-sim
CODE_SIGNING_ALLOWED=NO build`, then `simctl install/launch` with
`SIMCTL_CHILD_HOP_DEV_TOKEN=<daemon sessionSecret>` (bypasses TOTP; the daemon
accepts it as Bearer/?token=) and optional `SIMCTL_CHILD_HOP_DEV_OPEN=<session>`
to auto-open a terminal. Screenshot: `simctl io <udid> screenshot out.png`.
Probe sessions: create with `X-Hop-Actor: agent`, delete in a finally.

## ROOT CAUSE of "server refused the connection" (2026-07-25, fixed)
`Cookie` is a RESERVED URLSession header: a manually set one is stripped while
URLSession manages cookies itself — and its own jar skips Secure cookies for a
`wss://` URL (scheme isn't https). So NEITHER path sent the session cookie and
the daemon 401'd the upgrade (Cloudflare surfaces that raw 401 as **502**, which
is why the app said "refused"). Fix: `req.httpShouldHandleCookies = false`
before setting the explicit Cookie header. Verified in the simulator on the
cookie-only path (HOP_DEV_COOKIE) against hop.zhoulab.io — full color terminal.
Auth facts worth remembering: cookie name is `tunnel_session`; the daemon
accepts cookie | `Authorization: Bearer` | `?token=`; all four of
`/ws?room=` and `/s/<name>/ws` × cookie/bearer/token work through the tunnel.

## SECOND root cause: "refused (101)" = 1 MB WebSocket message cap
101 is Switching Protocols — the upgrade SUCCEEDED; the failure was right after.
URLSessionWebSocketTask defaults to a **1 MB maximumMessageSize**, but hop
replays a join snapshot of up to 1.5 MB (HAY_SNAPSHOT_REPLAY_BYTES) in ONE
message — so every session with real scrollback died on connect while the tiny
probe sessions used for testing worked. Fix: maximumMessageSize = 32 MB, and the
error mapping no longer calls a 101 "refused" (post-connect failures now report
the real cause). Verified in the simulator against Solstice, a heavy live claude
session, over the tunnel: full scrollback rendered.
LESSON: test against a REAL session with history, not a fresh probe.

## Fixes from the first on-device round (2026-07-25)
- **WS connect failed while REST worked** — URLSession does not attach `Secure`
  cookies to `wss://` (scheme isn't https), so the daemon 401'd the upgrade.
  Now the session cookie is set explicitly on the WS request (+ optional Bearer/
  ?token=), and failures print the real reason (401/404/network) in the terminal.
- **Transient blip logged you out** — any non-JSON/failed /api/sessions marked the
  app unauthenticated; now only 401/403 (or an HTML login page) does.
- Accessory keys wrapped to two lines ("es/c") → fixed widths, no wrap,
  horizontally scrollable, added paste + keyboard-dismiss.
- Terminal nav bar was an empty black void → inline `● name` + app capsule.
- Dark appearance app-wide; purple capsule showed claude's VERSION string
  ("2.1.220") → version-looking values now render as "claude".

## v1 (2026-07-25): remote + native polish — ON DEVICE PENDING VERDICT
- Direct hop.zhoulab.io: native login (POST /api/login, password+TOTP) → 7-day
  session cookie in the app's URLSession → carried by REST + wss automatically.
  No LAN bridge needed (tools/lan-bridge.mjs stays as dev fallback).
- Native UI: hop-branded login (hare + wordmark, purple), sessions home screen
  (attention-first sort, live dots, bell ring+icon, app capsules, ~cwd, relative
  time, pull-to-refresh, 5s auto-refresh), terminal with nav state dot, key
  accessory bar (esc/tab/sticky-ctrl/arrows/paste) above the iOS keyboard,
  distinct haptics for bells vs keys. Display name: "hop".
- Not yet: app icon asset, Face ID/keychain credential save, reconnect-in-place,
  session create/rename/kill, push notifications (next big rock).

## Loop iterations (autonomous, every 10 min)
1. **App icon** — hop's purple prompt chevron, CoreGraphics-rendered 1024 opaque
   full-bleed (iOS masks corners, rejects alpha). Matches the web favicon.
2. **Bell notifications (local)** — HopNotifier posts a UNNotification when a
   session's bellSeq passes this device's seen marker; banner shows even in
   foreground, tap opens that session, delivered notifications clear when you
   open it, toggle lives in the list's ⋯ menu.
   **Bug found while testing**: sessions never opened on this device could NEVER
   show attention — the seen marker defaulted to the CURRENT bellSeq, so
   `attention` was always false. Baselines are now seeded (silently) on first
   sight, matching the web client. Verified live: a real `\a` in a session lit
   the red ring + bell icon within one poll.
   Still device-only: the OS permission prompt needs a human tap (Simulator
   can't), and true background/closed-app delivery needs the APNs server piece.

3. **Auto-reconnect** — iOS suspends the socket on background; returning left a
   dead terminal until you found the menu item. Now: reconnect on foreground
   whenever the socket isn't live, plus self-healing retry with backoff
   (1/2/4/8s, capped 15s) for tunnel blips, reset on a healthy connect and
   cancelled on manual reconnect/leave. Verified by a real background→
   foreground cycle in the simulator: terminal came back live unattended.

4. **Live previews in the session list** — /api/sessions/preview for the top 6
   visible live sessions, refreshed every 9s only while the list is on screen
   (the daemon renders these on demand, so the cost is bounded). Shown as a
   3-line monospace block per row.
   **Design catch found by looking at it**: a naive "last 3 non-empty lines"
   showed every Claude session as identical composer box-drawing. Previews now
   skip TUI chrome (box characters, prompt-only lines, "bypass permissions" /
   "esc to interrupt" hints) and keep the last real content lines — so rows now
   read "Incubating… (10m 53s · 7.3k tokens)", "Ran 2 shell commands", etc.

5. **Presence & control** — the client now parses presence/collab/hello and
   input_rejected: the title bar shows a viewer count (and a lock badge when
   someone else holds control, a raised-hand when you do), the ⋯ menu lists
   viewers with a typing marker and offers lock-typing-to-one-user plus
   take/release control, and a refused keystroke surfaces the server's reason
   as a toast instead of vanishing. Verified live: a second client attached
   over the tunnel appeared as "👥 2" within a second.

6. **Agent access + saved password** — long-press a session to allow/block
   agent (MCP) access, with a purple cpu marker on rows where agents may drive;
   login can remember the PASSWORD in the keychain (device-only, never synced,
   never the TOTP secret — both factors on one device would defeat 2FA), so a
   7-day cookie expiry costs one 6-digit code instead of a full re-entry.

7. **Tests + error visibility** — six features had shipped with zero
   regression cover, and the one real logic bug (attention baseline) was caught
   only by luck in live testing. Added a unit-test target (8 tests) over the
   pure logic: attention/seen-marker semantics (the shipped bug, now pinned),
   preview chrome-stripping, version→"claude" badge, ~cwd shortening,
   scope/filter matching, port exclusion. List filtering moved out of the view
   into a testable `filterSessions`. A failed refresh now shows an orange
   banner in the list — `lastError` was being set and never displayed.
   Run: `xcodebuild test -scheme HopSpike -destination 'platform=iOS
   Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`

8. **Robustness + terminal ergonomics** — the server field now accepts what
   people actually type ("hop.zhoulab.io", a pasted URL with a trailing slash,
   stray whitespace): it defaults to https and trims, instead of failing login
   with no explanation (covered by tests, and the keychain account + WS cookie
   lookup use the same normalized origin). A "Live" pill appears when you
   scroll into scrollback and snaps back to the live edge. Pinch anywhere on
   the terminal to size the text (persisted, same 8–24 bounds as the menu).
   9 tests green.

9. **Unreachable-server hang + wasted polling + empty states** — found by
   pointing the app at a dead host: it sat on the launch spinner FOREVER with
   no escape (waitsForConnectivity parks the request indefinitely and no
   timeouts were set). Now requests fail fast (12s request / 25s resource) and
   you land on login with "Could not connect to the server." Previews no longer
   poll while a terminal is pushed on top of the list (the daemon was rendering
   screens nobody was looking at). Empty/unreachable/no-match states are real
   views with an action (Try again / New session) instead of one line of prose.

10. **Switch sessions from inside a terminal** — the title is now a menu of
   the other live sessions (attention marked, agent sessions flagged); picking
   one swaps the terminal in place instead of popping back to the list. Also:
   landscape orientations declared explicitly.
   **Tooling bug found**: the unit tests run inside the app host and
   AppModel.serverURL is @AppStorage-backed, so `testServerURLNormalization`
   was writing 127.0.0.1:8080 into the INSTALLED app's real settings — a test
   run left the app pointed at a dead server. The test now saves and restores
   the value. (Simulator note: `simctl spawn defaults delete` doesn't reliably
   clear an app's defaults; uninstall the app instead.)

11. **Repo is now self-sufficient** — added a README (what it is, quick start,
   layout, hop API contract, the two iOS traps that cost real debugging, dev
   env vars) and a Makefile so nobody has to remember flags:
   `make test` / `make install` / `make sim [OPEN=Session]` / `make shot`.
   Both verified end-to-end (tests green, signed install to the phone on the
   first attempt). This is what makes the project genuinely droppable — and
   picked back up — rather than dependent on one session's memory.

12. **Background bell polling** — local notifications only fired while the app
   was running, so a bell rung with the phone in a pocket was simply missed.
   Registered a BGAppRefreshTask (id io.zhoulab.hop.spike.refresh, scheduled
   whenever the app backgrounds) that polls /api/sessions and posts the same
   notifications. iOS decides the cadence (opportunistic, typically tens of
   minutes) — this narrows the gap but does NOT replace APNs, which is still
   the only way to be woken immediately with the app closed.
   Required moving off GENERATE_INFOPLIST_FILE to an explicit Info.plist
   (UIBackgroundModes / BGTaskSchedulerPermittedIdentifiers are arrays that
   INFOPLIST_KEY_ settings can't express); display name, orientations and
   launch screen carried over and verified in the built plist.

13. **Project grouping + a JSON parsing bug the tests caught** — with ~30
   sessions a flat list is a scroll, so `⋯ → Group by project` buckets rows by
   the first couple of path segments under home (`~/Code/hop2` holds the repo
   root AND its subdirs), most-recently-active bucket first. Filtering always
   flattens — when you're hunting one thing you don't want buckets.
   Writing the test for it exposed a real bug: `json["lastActivityAt"] as?
   Double` silently yields nil when the value arrives as an integer, and the
   same pattern guarded `bellSeq` — i.e. one encoder change away from ordering
   and ATTENTION both quietly reading zero, with no error anywhere. Both now go
   through Int/Double/NSNumber coercion, pinned by a test. 11 tests green.
   Build note: three successive "unable to type-check this expression in
   reasonable time" failures forced splitting SessionsView's body into small
   computed pieces. That's a compile-time cliff, not a style preference — it's
   commented in the file so it doesn't get "cleaned up" back into one chain.

14. **Hold-to-repeat on the key bar** — holding ↓ or ⇞ now repeats like a real
   keyboard (instant first keystroke on touch-down, then 0.42s delay → 55ms
   cadence) instead of demanding one tap per line. Navigation keys only: a
   stuck ^C or a repeating paste is destructive, and a repeating modifier would
   just flap its armed state — pinned by a test. Repeating keys fire on
   touch-DOWN and drop their touch-up action, so a hold never sends a trailing
   extra keystroke on release.

15. **App-icon badge** — the count of sessions wanting you now rides on the
   home-screen icon, which is the thing a web client structurally cannot do:
   you see "3" without opening anything. It tracks the LIVE count rather than a
   running total, so reading a session drops it (immediately on open, via a
   recount of what's still delivered; otherwise on the next refresh). Background
   refresh updates it too, so the badge stays honest with the app closed.

16. **Typing into a dead socket now says so** — keystrokes sent while
   disconnected went nowhere silently, and since a terminal's echo comes from
   the SERVER, that reads as a frozen app. Input while down now raises
   "Not connected — reconnecting…" (throttled to one per 3s so a burst of
   typing isn't a burst of toasts). Deliberately not queued for replay: a
   command landing 30s late, mid-something-else, is worse than one that plainly
   didn't happen. ctrl/alt/dismiss keep working while down — they're local.
   Also tried **time-sensitive notifications** (break through Focus, which is
   right for a waiting agent). Worth knowing: the wildcard "iOS Team
   Provisioning Profile: *" SILENTLY STRIPS the
   com.apple.developer.usernotifications.time-sensitive entitlement — build
   succeeds, no warning, and `codesign -d --entitlements -` shows it missing.
   Removed the dead entitlements file; `interruptionLevel = .timeSensitive`
   stays in code and starts working the moment the App ID carries the
   capability (a portal action, no code change). relevanceScore works today.

17. **Tap the links agents print** — PR URLs, preview servers, docs scroll past
   constantly and on a phone they were untouchable glyphs. `⋯ → Open link…`
   lists what's on screen (newest first, capped at 8 — a build log can print
   dozens) and opens it in Safari. Three details that make it actually work:
   sentence punctuation is trimmed but a BALANCED paren is kept
   (`…/a_(b)_c` survives, `(https://x)` doesn't); bare `localhost:5173` gets a
   scheme; and wrapped rows are rejoined first, since a terminal wraps a long
   URL with no newline and the naive read gives two broken halves. SwiftTerm
   keeps `BufferLine.isWrapped` internal, so the wrap is inferred the way
   terminals do it — a row that filled its last column ran on. The URL charset
   is explicit ASCII rather than "not whitespace" precisely because rejoining
   can butt a URL against a TUI border. All five cases are unit-tested (18).

18. **Home Screen quick actions** — long-press the hop icon for the top four
   sessions (attention first, with a bell icon and "Wants your attention";
   otherwise tagline or cwd) and land straight in one, skipping the list. The
   badge says how many want you; this says which.
   SwiftUI's App lifecycle has no hook for these — cold-launch actions arrive
   in `scene(_:willConnectTo:options:)` and warm ones in
   `windowScene(_:performActionFor:)`, both scene-delegate methods — so the app
   now installs a scene delegate that ONLY observes; SwiftUI's WindowGroup
   still owns the window (verified in the simulator: no black screen).
   Republish is gated on a change signature, since handing SpringBoard an
   identical array twelve times a minute is pure IPC for nothing.
   Verification note: quick actions live in SpringBoard, so no screenshot or
   test can see them. An os_log line is the evidence —
   `xcrun simctl spawn <sim> log show --last 60s --info --predicate
   'subsystem == "io.zhoulab.hop.spike"'` showed "published 4 quick actions".
   **Still worth one long-press on your phone to confirm the tap-through.**

19. **Audit of the last few iterations — two real defects in my own work.**
   Adding features fast is how you ship bugs quietly, so this round added
   nothing and went looking instead.
   - **Haptic drill**: hold-to-repeat (#14) routed every repeat tick through
     the same handler as a press, and that handler fires a haptic. Holding ↓
     was ~18 taptic pulses a second — a drill, plus the battery cost. The
     handler now knows whether it's a press or a tick; only the press buzzes.
   - **Timer that outlives the screen**: the repeat Timer is owned by the run
     loop, and capturing self weakly only makes its ticks HARMLESS, not
     stopped. Leave mid-hold (session ends, interactive back gesture) and
     nothing on the touch path ever calls endRepeat — it fires every 55ms for
     the rest of the process. Now stopped in didMoveToWindow(nil) and deinit.
   Also checked and found clean: HayClient's receive loop (weak self, recurses
   only on success), the reconnect backoff task (cancelled in dismantle),
   notification observers (removed in detach), preview polling (gated on the
   list being frontmost).

20. **Server & account (sign out)** — until now the only way off a server, or
   off an account on a phone you were handing to someone, was DELETING THE APP.
   `⋯ → Server & account` shows the address, session count and version, and
   signs out for real: the cookie (dropping only the flag would let the next
   launch walk right back in), the keychain password, the seen-bell baselines
   (stale ones would silence a new account's first bell), the badge and the
   quick actions — the last two leak session names to exactly the person you
   signed out for. Changing servers starts there: sign out, enter a new
   address.
   Closed a race while wiring it: a refresh already in flight sets
   `authenticated = true` on completion, which would bounce the user straight
   back in a second after signing out. Refreshes now carry an auth epoch and
   discard themselves if it moved.

21. **Attach claim — a protocol gap, found by reading hop's server.** Our
   client sent a bare `resize` on attach. hop elects the shared PTY size by
   typing recency: a plain resize needs every peer input-idle for 60s
   (RESIZE_CLAIM_IDLE_MS), while `claim: "attach"` needs only 2.5s
   (ATTACH_CLAIM_IDLE_MS) because opening a session somewhere is a deliberate
   act. So opening on the phone any time a desktop had typed in the last MINUTE
   lost the election and rendered at the desktop's width — mis-wrapped until
   you typed. The web client has sent the claim for a while (its comment calls
   it "one autofit away"); we now match it. The claimed size comes from the
   view's own layout, not read back off the terminal, which a peer's
   active_size may already have widened.
   Verified by log line, not by assumption: "attach claim 51x26 for Orion".
   **That log then exposed a second bug**: opening ONE session produced THREE
   connects. Becoming active while the first connect was still in flight tore
   it down and restarted it, because the reconnect fired on `status != .live`
   and `.connecting` isn't `.live`. Each connect pulls a fresh snapshot — up to
   1.5 MB — so that was ~4.5 MB on someone's cellular to open one terminal. Now
   gated on `status == .closed`: one connect, re-measured.

22. **Buffered input (reversing #16) + the typing signal.** Reading the web
   client's input path showed it does the opposite of what I chose in #16: it
   BUFFERS keystrokes through an outage and replays them, capped at 15s and 200
   entries. That cap answers the objection I'd raised — a command from a minute
   ago never lands mid-something-else — while a two-second tunnel hiccup no
   longer costs you a whole retyped command, which on a phone is the common
   case. Adopted: buffer, toast "Reconnecting — input buffered", replay in
   order as one message on reconnect, and SAY when stale input was discarded.
   The buffer is pure (`PendingInput`) and tested — order, the age cap, and the
   bound all break silently otherwise.
   Also: we parsed peers' `typing` state but never sent our own, so a desktop
   never saw the phone mid-command. Now sent on transitions with the web's 1.2s
   idle window.
   Key sequences moved from a switch full of send calls to `AccessoryKey
   .sequence`, so ESC[A/B/C/D and friends are pinned by a test rather than
   trusted. 22 tests.

23. **Polling that knows what it's connected to.** The list refreshed every 5s
   and previews every 9s regardless of network — on a cellular radio someone is
   paying for, with a render per visible session, that's the app being a bad
   guest in a pocket. NWPathMonitor now drives the cadence: Wi-Fi keeps 5s (so
   attention still feels immediate), cellular backs off to 12s/25s, and Low
   Data Mode goes to 30s and drops previews entirely — it's an explicit
   instruction from the user, not a hint, and previews are the nicety half.
   The intervals are a pure function with a test. Preview polling idles rather
   than returns when suppressed, so switching Low Data Mode off resumes it
   without needing the app backgrounded. 23 tests.
   This is a native-only capability: a web page polls at whatever rate it was
   written for.

24. **Background-task double completion + an accessibility pass.**
   - Audited the two files never reviewed. Keychain is correct (delete-then-add
     avoids errSecDuplicateItem; WhenUnlockedThisDeviceOnly is the right class).
     BackgroundRefresh was NOT: if iOS expired the slot while the refresh was
     still in flight — exactly what a slow tunnel causes — the expiration
     handler completed the task and then the refresh completed it AGAIN.
     Completing a BGTask twice is a hard error; iOS logs "was completed twice"
     and can stop granting background slots altogether, which would silently
     kill pocket bell notifications. Now single-shot under a lock, with the
     expiration handler installed BEFORE the work starts (an expiration in that
     window would have found no handler at all), and a log line so background
     runs are observable at all.
   - Accessibility: icon-only controls announced as SF Symbol names or nothing,
     which also breaks Voice Control. The key bar now speaks ("page up", not
     "⇞"), toolbar buttons are labelled, the hare is marked decorative, and a
     session row is ONE utterance leading with attention — not a dot, a badge,
     and three lines of raw scrollback read aloud. Pinned by a test. 24 tests.

25. **Preview correctness + the device checklist.** Two inconsistencies from my
   own earlier work: with grouping on (#13) previews were fetched for the top 6
   of the ATTENTION order while the list renders in GROUP order, so visible
   rows could sit preview-less while off-screen ones stayed fresh — the fetch
   now follows the rendered order. And the preview cache was never pruned, so a
   killed session's last screen stayed in memory and would resurface if the
   name were reused.
   Also tried and abandoned simulator rotation: driving it needs synthetic
   keystrokes through System Events, which land in whatever app is frontmost —
   it hit a browser window instead of the Simulator. Not worth touching the
   user's other apps for a screenshot; landscape moved to the device checklist.
   Added that checklist at the top of this file: 11 ordered checks, each one
   something built and instrumented here but impossible to exercise without a
   phone in hand.

26. **Find in scrollback was one-shot; and APNs is blocked on more than a
   greenlight.**
   - Find only ever returned the NEWEST match: every "search again" restarted
     at the live edge, so an earlier occurrence — the one you're usually
     hunting when you search a terminal for "error" — was unreachable. It also
     re-ran on every view update, so the list's 5s background refresh yanked
     you back to the match while you were reading around it. Find is now a
     REQUEST with a sequence number (runs exactly once) plus ↑/↓ stepping from
     the last match, and it distinguishes "no earlier match" from "not found".
     The stepping logic is a pure function over a line accessor — testable
     without materialising thousands of scrollback rows. 27 tests.
   - **APNs finding, verified not assumed**: the signed app carries only
     application-identifier, team-identifier and get-task-allow. Adding
     `aps-environment` and rebuilding with `-allowProvisioningUpdates` changes
     nothing — Xcode keeps using the wildcard "iOS Team Provisioning Profile:
     *" and strips it silently, exactly as it did for time-sensitive (#16).
     Apple does not allow Push on a wildcard App ID. So APNs needs THREE
     things, not one: (1) `io.zhoulab.hop.spike` registered as an EXPLICIT App
     ID with Push enabled — Xcode UI or the portal, not the command line;
     (2) an APNs auth key (.p8) for the daemon; (3) the daemon endpoint. Step 1
     is a couple of minutes and is a prerequisite for any client work, so it's
     worth doing before the greenlight rather than after.

27. **Pinch-to-zoom was silently reverted.** The gesture set the font on the
   UIView and persisted it, but never told SwiftUI — and `updateUIView`
   rewrites the font from `fontSize` on EVERY update. So pinching worked for a
   moment and then snapped back at the next toast, presence change or list
   refresh, with the new size only appearing the next time the terminal was
   opened. It now reports the size up through a callback, which is the single
   source of truth. (Checked the same class of bug across the rest of
   updateUIView — font was the only prop the coordinator also wrote.)
   Extracting the fix hit the SwiftUI type-checker cliff a fourth time; the
   terminal's body is now split like SessionsView's, for the same reason.

28. **Notified about the terminal you're looking at.** A bell rung while you
   were watching a session produced a banner and a haptic OVER that session —
   and then, because the seen marker was only written `.onAppear`, backing out
   left a stale attention dot for something you'd just watched happen. Now the
   marker stays current while the session is on screen, and alerts skip the
   watched session (badge included).
   The obvious fix has a trap worth naming: "watched" must mean watched RIGHT
   NOW. Locking the phone with a terminal open leaves the session marked open,
   so a naive version would suppress background notifications for precisely the
   session you were waiting on — silencing the app's whole reason to exist.
   Suppression is therefore gated on the app being in front, and the identity
   is re-checked on disappear because switching sessions can appear-then-
   disappear and a blind clear would wipe the new one. 28 tests.

29. **A session ending under you blanked the screen.** When an agent finishes
   and its process exits, hop drops the session; the next list refresh removed
   it, the navigation destination found nothing, and the terminal you were
   reading went blank — taking the final output with it. The destination now
   falls back to the last known value, so the terminal stays up with its
   "[session ended]" line and you can still read (and copy) what it left.
   Related, found in the same pass: a permanently dead room was retried
   forever. A 404 ("session not found") or a 401/403 went down the same
   backoff path as a network blip, so the client kept redialling a room that
   no longer exists and repeating the error. Failures now say whether they are
   permanent, and permanent ones stop.
   Checked and found sound: local bell haptics (SwiftTerm's parser owns OSC
   state, so a title-update BEL never reaches the bell delegate — the same
   distinction hop's server makes server-side), and create-navigation
   (hop's toInternalSessionName is identity for valid names, so the typed name
   IS the room). 28 tests.

30. **Login — the screen you touch every 7 days.** Reviewed it for the first
   time and it was full of friction: a number pad has NO return key, so after
   typing six digits there was no submit gesture at all — you had to reach for
   the button. Nothing was focused on launch, so every login started with a
   tap. A code copied from an authenticator ("123 456") just failed. And the
   remembered password wasn't re-read when the server address changed, so a
   previous server's password sat in the field.
   Now: focus lands on the first empty field, the code is cleaned to six digits
   as you type, login fires automatically on the sixth digit, a failed code is
   cleared (it's single-use — a spent one is never worth resubmitting) and
   refocused, and the password follows the server it belongs to. Re-login with
   a remembered password is now: open, type six digits, in.
   The screenshot loop earned itself again here: setting @FocusState
   synchronously in onAppear is silently dropped (the view isn't in a window
   yet), so the "auto-focus" I'd just written did nothing at all. Visible
   instantly in a screenshot, invisible to the compiler and the tests.
   29 tests.

31. **Four server messages were being dropped on the floor.** hop's server
   sends twelve message types; we handled eight. The two that mattered:
   - `error` — the server sends this when WE send something it can't parse.
     Dropping it meant a protocol drift after any hop update would break input
     with no signal anywhere: no toast, no log, nothing to grep. It now toasts
     and logs at error level.
   - `session_renamed` — renaming from the desktop left the phone's title stale
     until the next list refresh. The title now updates live.
   `pong` and `cwd_changed` are explicitly ignored (we never ping; the list
   refresh carries cwd), and anything genuinely unknown now logs — naming what
   we ignore is how the NEXT protocol addition gets noticed instead of joining
   these four. Verified against the live daemon: no unhandled types, no errors.
   Also applied #13's lesson to `active_size`, which still used `as? Int` — the
   coercion helpers are now shared between the HTTP and socket paths rather
   than living privately in one of them. 29 tests.

32. **A stale error banner that never went away.** `lastError` was set on
   failure and NEVER cleared on success, so a single tunnel blip pinned a red
   banner to the top of the session list for the rest of the launch — through
   every successful refresh after it. The app looked broken while working
   perfectly. A refresh that succeeds now clears it.
   Second half: `post()` collapsed every rejection into "Request failed",
   discarding what hop actually said. Verified the real shape with curl rather
   than assuming — `POST /api/sessions` with a bad name returns 400
   `{"error":"Invalid session name"}` — so creating a session with a space in
   the name now says exactly that, instead of a dialog that closes and appears
   to do nothing. 29 tests.

33. **Soak test + a scrollback finding that came out smaller than it looked.**
   - **Soak** (never done before): list view polling for 6 minutes — RSS flat at
     234 MB, zero errors. Terminal open on a busy session for 3 minutes — flat
     at 343 MB. No leak in either, which is the first real evidence for the
     "left open in a pocket" case.
   - **Scrollback**: SwiftTerm keeps 500 lines by default while hop replays up
     to 20 MB of raw stream on reattach, so we were parsing far more history
     than we kept. Raised to 5000 (matching the find walk's own limit); the
     measured memory cost was nil.
     BUT the honest result: measuring reachable depth on a claude session gave
     **26 lines** — the visible screen. TUI apps run in the ALTERNATE screen
     buffer, which by definition has no scrollback, so for agent sessions this
     change does nothing and "find/copy all scrollback" can only ever see the
     current screen. That's terminal semantics, not a bug — worth writing down
     so it isn't re-investigated. The change helps plain shell sessions, where
     the raw replay does fill the normal buffer and 500 was clipping it.
   - Two SwiftTerm internals blocked measurement (`yBase` after `isWrapped`);
     depth is now counted through the same public accessor find and copy-all
     use, which is the number that actually matters. The reachable depth is
     logged per session open.

34. **Exercised the 7-day expiry — the one failure you're guaranteed to hit.**
   Fed the app a garbage session cookie. Good news first: it lands cleanly on
   the login screen, keyboard up, no hang, no spinner, no confusing error.
   But it arrived with NO explanation, which reads as "something broke" rather
   than "it's been a week", so the login screen now says so — and only when a
   cookie we HELD was rejected, never on a first run.
   Two things that took measurement rather than reasoning:
   - hop answers an invalid token with **200 and an HTML login page**, not 401
     (confirmed by curl). The client already handled that; worth knowing.
   - The obvious implementation didn't work, and the log said why: the rejected
     response carries a Set-Cookie that CLEARS the cookie, so by the time the
     failure is handled the jar is empty and "expired" is indistinguishable
     from "never signed in". The check now reads cookie state BEFORE the
     request. General lesson: test a precondition before the operation that
     destroys it.
   - And the first working version silently TRUNCATED to "…7 da…", because a
     SwiftUI Label won't wrap without fixedSize. Three screenshots to get one
     sentence on screen correctly.

35. **Measured what opening a session actually costs: 2.4 MB for one screen.**
   Instrumented the join snapshot. Opening a claude session pulls a
   **2439 KB** WebSocket message (98 ms on Wi-Fi) — and #33 measured what
   survives it: **26 reachable lines**. On cellular that's several seconds and
   real money per open, for one screenful.
   Where it comes from, read from hop's own source:
   - The server already bounds join replay — `HAY_SNAPSHOT_REPLAY_BYTES`,
     default 1_500_000 — and its comment names this exact case ("a phone on a
     tunnel downloads and parses all of it before first paint").
   - But the wire cost is ~60% ABOVE that bound, because the snapshot is JSON
     and every ESC byte becomes `\u001b`. Escape-dense TUI output escapes
     badly: 1.5 MB of raw stream → 2.4 MB of JSON.
   - `ws` is constructed with no perMessageDeflate, so nothing is compressed.
     Enabling it would help the browser a lot; it would NOT help this app,
     since URLSessionWebSocketTask doesn't negotiate permessage-deflate.
   **The cheap win is yours and needs no code**: lowering
   `HAY_SNAPSHOT_REPLAY_BYTES` (say to 300_000) would cut mobile opens roughly
   5–8× and cost agent sessions NOTHING — alt-screen apps redraw in full, which
   is why the reachable depth is 26 lines either way. It shortens restored
   scrollback for plain shell sessions, which is the whole tradeoff.
   The snapshot size and latency are now logged per open, so any change to that
   env var can be verified from the phone rather than assumed.

36. **Snapshots were replayed into a dirty terminal.** hop's web client calls
   `term.reset()` before writing a snapshot and says why in a comment: stale
   cursor column, SGR attributes, and leftover alt-screen / mouse-reporting
   modes otherwise bleed across the reconnect — the symptom it records is mouse
   reports landing as junk input ("35;197;31M") at a prompt that never asked
   for them. We reset nothing: the replay was fed straight into the existing
   terminal, which also DUPLICATES history for normal-buffer (shell) sessions,
   since the tail gets appended a second time.
   That path runs on every return from background, which on a phone is
   constantly. Snapshots are now distinguished from ordinary output and land on
   a terminal reset first (`resetToInitialState`, which rebuilds from options
   and so keeps the 5000-line scrollback from #33).
   Verification limit worth recording: the simulator does NOT truly suspend a
   backgrounded app, so the socket survives and no reconnect happens — I
   confirmed the first-snapshot path renders correctly but could not exercise
   the reconnect one here. Added to the device checklist.

37. **Seeded the modes my own reset cleared — and found a 10x mobile win that
   needs 3 lines in hop2.**
   - #36's reset was right but incomplete. hop's snapshot carries
     `alternateScreen`, `cursorHidden`, `keyboardEnhanced`, `mouseReporting`,
     `mouseSgr` precisely BECAUSE the replayed bytes don't re-emit the DECSETs
     that turned them on — the app enabled alt-screen once, long before the
     tail begins. We ignored all five. Alt-screen and cursor-hidden are now
     re-entered as sequences after the reset (SwiftTerm keeps the buffer switch
     private, and a terminal takes modes as sequences anyway).
     Mouse reporting is deliberately NOT restored: on a touch screen a tap is
     how you reach the keyboard, and turning taps into clicks at the app is a
     behaviour change to decide on a device, not guess at here. Same for the
     Kitty keyboard flag — left as is.
   - **`replayBytes` is honoured by rooms.ts and populated by nobody.** The
     per-client replay bound exists in the server's type and its Math.min, but
     index.ts never reads it off the URL, so no client can ask for a smaller
     snapshot. The app now sends `replayBytes=200000` regardless: harmless
     today (unknown params are ignored — verified, still 2447 KB), and it
     becomes a ~10x cut the moment the server reads it.
     **CORRECTED in iteration 54 — no hop2 change is needed at all.** The
     param is read by `scripts/hay-host.js`, not `hay/apps/server/src/index.ts`,
     and it is called **`replay`** (bytes), not `replayBytes`. Sending the wrong
     name was silently ignored, which is what made this look like missing server
     plumbing. With the right name: snapshot **2447 KB → 339 KB, 98 ms → 4 ms**.


38. **Paste was executing your multi-line text line by line.** The accessory
   paste key read the clipboard and sent it straight down the socket, bypassing
   SwiftTerm — which means bracketed-paste markers were never added. With
   bracketed paste on (claude has it on), a pasted multi-line command or prompt
   should arrive as ONE paste; sent raw, every newline executed a line.
   Pasting is precisely what you do on a phone instead of typing, so this was
   in the way of the main workflow. Paste now goes through `view.paste(nil)`,
   which wraps it in ESC[200~/ESC[201~ when the app asked for it and still
   lands in `deliver()`, so offline buffering keeps working.
   Also deleted `AccessoryKey.sendsInput`: dead since #22 moved the connection
   check into `deliver()`, and referenced only by a test — a test asserting
   properties of code nothing calls, which is worse than no test. Replaced with
   one that pins what actually matters (paste has no static sequence).
   **Process note**: the first attempt at that deletion removed 16 unrelated
   tests, because the edit sliced from one function to another far later in the
   file. The suite count (13 instead of 29) is what caught it. Restored from
   git and redone with an exact-match assert.

40. **Search inside sessions, not just their names.** Audited every REST call
   against the daemon: all five paths exist and all three payload shapes match
   (`{oldName,newName}`, `{internalName,allowed}`, `{name,internalName}`) —
   nothing broken, and now verified rather than assumed.
   The audit turned up endpoints we never used, one of which matters a lot on a
   phone: `/api/sessions/search?q=` searches the SCROLLBACK OF EVERY SESSION
   server-side and returns snippets. The local filter only ever matched names,
   cwds, apps and taglines — but the question you actually have on a phone is
   "which session mentioned that error", and you cannot answer it by opening
   thirty terminals.
   The list now shows a "Found in output" section with the matching session and
   its snippet; tapping opens it. Debounced 450 ms and gated at two characters,
   because each query is a server-side scan of every session.
   Verified against the live daemon: searching "scrollback" surfaced Neptune,
   Orion and sequencebrowser, none of which match by name.
   Unused endpoints noted for later: /park, /archive, /screen, /tagline,
   /move, /reorder, /origin, /restore, /claim-local-cli.

41. **Fast first paint — the blank-terminal wait is gone.** Opening a session
   showed nothing until the 2.4 MB snapshot finished; on Wi-Fi that's ~100 ms,
   on cellular it's the whole wait. hop's web client solved this long ago and
   its comment names our exact case ("the dominant switch cost on a phone over
   the tunnel"): `/api/sessions/screen` serializes the session's CURRENT screen
   from the preview grid in one small response.
   The app now fires that HTTP request alongside the WebSocket connect and
   paints it immediately — measured at **1 KB, landing 29 ms before the 2454 KB
   snapshot**. It paints at the session's real dimensions (writing a wide
   screen into a narrow grid wraps it into mush) and is fully superseded,
   because #36's snapshot handler resets the terminal before writing. Entirely
   best-effort: any failure just restores the old blank-until-snapshot
   behaviour.
   Found by continuing the endpoint audit from #40 — `/screen` returns
   `{data, cols, rows}` WITH escape sequences, unlike `/preview`'s plain text.

42. **Field-level API audit: mostly a negative result, plus one thing you
   should know.** Dumped a live session object and compared against what the
   client parses. Ignored fields: `attached`, `cols/rows`, `createdAt`,
   `folderId`, `hasLocalCli`, `localCliCount`, `hostPort`, `lastBellAt`,
   `taglineAt`, `windows`.
   - `folderId` is null on all 19 sessions and `/api/folders` isn't live, so
     hop's folders aren't in use — the cwd grouping from #13 stands rather than
     being replaced by folder grouping.
   - `hasLocalCli` is false everywhere, `attached` is true on 17/19. Real but
     low-value; noted, not built on.
   - **Your running daemon is behind its source.** `park`, `archive`,
     `restore`, `tagline` and `/api/folders` all exist in ~/Code/hop2 but
     answer "Unknown API endpoint (daemon may need a restart to pick up new
     endpoints)". Only `screen` is live, which is why #41 works. So the recent
     park/stop-resumable work isn't running, and any mobile feature built on
     those endpoints would fail until a restart — deliberately not built.
     Same applies to the `replayBytes` wiring from #37.
   Closed a test gap found along the way: `relativeTime` was untested and
   encodes the assumption that `lastActivityAt` is epoch MILLISECONDS. If hop
   ever sent seconds every row would read "56y" and nothing would fail loudly.
   Now pinned, including clock skew — a host clock slightly ahead of the phone
   gives a negative age and must read "now", never "-4s". 30 tests.

43. **"No signal" and "hop is down" are different problems.** The app reported
   both as whatever URLError said — "A server with the specified hostname could
   not be found" points you at the daemon when the actual problem is that
   you're in a lift. NWPathMonitor (already there from #23) knows the
   difference, so offline now says so, and the poll loop stops waking the radio
   to fail while there's no path (it resumes the moment one appears).
   **The screenshot then found the real bug.** Forcing offline showed a
   completely normal list, because bootstrap's first fetch had already
   succeeded — so offline looks EXACTLY like live: same rows, same relative
   times quietly going stale, no indication whatsoever. You'd read a
   ten-minute-old list believing it was current. The empty state I'd just
   written only helps when there are no sessions at all, which is the rare case.
   The list now carries an explicit "Offline — this list may be out of date."
   banner whenever there's no path, cached sessions or not. Verified on screen.
   Added HOP_DEV_OFFLINE=1 (`make sim OFFLINE=1`) because a simulator borrows
   the host's network and can't otherwise reach this state.

44. **Dead-code sweep (clean) + two things session output could do unannounced.**
   Swept every declaration for references, after #38 found `sendsInput` shipped
   unreachable WITH a test asserting it. All 11 candidates turned out to be
   framework-called protocol conformances (UIViewRepresentable, SwiftTerm's
   delegate) — no dead code. A clean result, and cheap to re-run.
   Reading those delegates found two places where session output — which for an
   agent session is arbitrary command output — acted on the phone unannounced:
   - **OSC 8 hyperlinks** opened ANY scheme. A `tel:`, `facetime:` or
     app-scheme URL would turn a tap on what looks like a link into an action
     nobody asked for. Now http/https only, and it says so when it refuses.
   - **OSC 52** let a session WRITE the clipboard silently. On iOS that
     clipboard is shared with every app and mirrored to the Mac by Universal
     Clipboard, so an unannounced replacement of what you had copied is the
     unacceptable part — not the write itself. Deliberately NOT blocked (hop's
     web client swallows it, but a browser has little choice: clipboard writes
     without a user gesture are restricted; and `yy` in vim reaching the iOS
     clipboard is a real workflow). It now toasts "Clipboard set by session",
     so it can never be silent.
   Worth noting I reversed my own first implementation here: refusing OSC 52
   outright would have quietly removed a working feature to fix a problem that
   was really about silence.

45. **Every build now identifies itself.** The Account sheet said "1.0 (1)"
   after thirty-odd installs, so "is the fix I'm testing actually on this
   phone?" was unanswerable — which matters a lot for the device checklist,
   where the whole point is testing specific fixes. CFBundleVersion now comes
   from the commit count and a HopGitDescribe key carries `git describe
   --always --dirty`, both passed on the xcodebuild command line. The sheet
   reads "1.0 (55) · cc6c8a8-dirty".
   **Trap worth recording**: `Sources/HopSpike/Info.plist` is GENERATED by
   XcodeGen from `project.yml` on every build, so my first attempt — editing the
   plist directly — was silently discarded, and the built app still said "1".
   The keys have to live in `project.yml`'s `info.properties`; there's now a
   comment there saying so. This is the same class of mistake as editing a
   build artefact: it works locally until something regenerates.

46. **White flash on launch, on a light-mode phone.** The app forces dark mode,
   but a LAUNCH screen follows the system appearance, and `UILaunchScreen: {}`
   names no colour — so on a phone set to light mode, opening hop showed a full
   WHITE screen before the dark UI appeared. Verified by setting the simulator
   to light and screenshotting mid-launch: solid white. Now backed by a black
   colour asset; re-verified in light mode: black, no flash.
   This one is invisible if you only ever test in dark mode, which is what I'd
   been doing for 45 iterations — `xcrun simctl ui <sim> appearance light` is
   worth remembering.

47. **Light-mode sweep (clean) — and it found the preview-corruption bug Jian
   reported weeks ago, in hop, with evidence.**
   Sweep first: with the simulator in light appearance, the list, terminal,
   system keyboard, search field and Account sheet all render dark correctly —
   the forced `.preferredColorScheme(.dark)` propagates even to the keyboard.
   #46's launch screen was the only light-mode defect.
   Then a preview in that screenshot read **"Enter to  elect · ↑/↓ to  avigate"**
   — the "s" of select and the "n" of navigate simply gone. This is Jian's
   earlier report ("session view preview sometimes displays in incorrect format
   but can recover"), and it is NOT a client bug:
   - `curl /api/sessions/preview?name=rooms` returns the dropped characters
     already, so the daemon is producing them.
   - Preview text comes from `readGridScreen` (hop:~5195) — a headless xterm.js
     grid fed incrementally via hay's `getOutputSince` cursor.
   - `getOutputSince` handles trimming correctly, BUT its `reset: true` path
     (stale/first cursor) returns `tailOutput(maxBytes)`: a RAW tail starting at
     an arbitrary character. hop then disposes the grid, builds a fresh
     headless term, and writes that tail (hop:~5256-5293).
   - TUI output is escape-dense, so an arbitrary cut lands inside an escape
     sequence often. The fresh parser eats the fragment plus the character
     after it — exactly one letter missing right after an attribute change,
     which is the symptom. It "recovers" because later deltas repaint.
   - hop's OTHER replay path already guards against precisely this:
     `boundSnapshotReplay` moves the cut past the first newline "so a partial
     escape sequence can't corrupt the replay". The grid-reset path has no
     equivalent.
   **Suggested minimal fix (hop2, for Solstice — not applied here):** in
   `hay/apps/server/src/rooms.ts`, `getOutputSince`, apply the same
   first-newline trim to the `reset: true` tail that `boundSnapshotReplay`
   already applies. Fixing it there fixes every consumer: the web switcher
   tiles, the iOS row previews, and the iOS fast paint, which all read the same
   grid.
