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

## Current state (updated by Orion)
- **Scaffolded**: XcodeGen project (`project.yml` → HopSpike app), SwiftTerm via SPM.
  ~250 lines Swift: ConnectView (bridge URL + session form) → TerminalScreen
  (SwiftTerm `TerminalView` + `HayClient` speaking the hay WS protocol:
  snapshot/output → feed, input → send, active_size → resize, bell → native haptic).
- **Compile: GREEN.** Full simulator build succeeds — SwiftTerm integration,
  HayClient, and the delegate wiring are all valid; Metal toolchain installed.
  Only signing separates us from the device build.
- **LAN bridge**: `tools/lan-bridge.mjs` — spike-only TCP proxy exposing the
  hay-host WS to the LAN (no hop2 changes needed). Security caveat printed at start;
  run only while testing.
- Toolchain verified: Xcode 26.6, iOS 26.5 SDK, xcodegen, Apple Development
  identity for team 7U9ZU5QLGQ present, iPhone 17 Pro known to devicectl.

## Needs from Jian  ⚠ BLOCKER first item
1. **Sign in to your Apple ID in Xcode** (Xcode → Settings → Accounts): the
   development certificate for team 7U9ZU5QLGQ is in the keychain, but there is
   no account session, so automatic provisioning can't mint a profile for
   `io.zhoulab.hop.spike`. One sign-in unblocks the device build.
2. **Plug in / unlock the iPhone** when we're ready to install (devicectl shows it
   "unavailable" until connected + trusted; Developer Mode must be on:
   Settings → Privacy & Security → Developer Mode).
3. First install will ask to trust the developer cert on-device
   (Settings → General → VPN & Device Management).

## Device checklist (10 minutes, unblocks v1) ⚠ ONLY YOU CAN DO THESE

Ordered by what's most likely to be wrong and what it costs if it is. Each was
built and instrumented here but CANNOT be exercised without a hand on a phone.

If something looks wrong, the app says why in the log: **Console.app → your
iPhone → search `io.zhoulab.hop.spike`** (Action → Include Info Messages).
README has a table of what each line means. `log collect --device-udid` would
be the scriptable route but needs admin, so Console is the practical one.

1. **Keyboard feel — the thesis the app rests on.** Type a real command with
   dictation and autocorrect. If this doesn't beat the web client, nothing else
   in this repo matters.
2. **Hold-to-repeat.** Hold ↓ at a shell prompt: history should walk smoothly,
   and it should buzz ONCE, not continuously. (A haptic-per-tick bug lived here
   for five iterations — #19.)
3. **Buffered input through a drop.** Start typing a command, flip Airplane
   Mode on mid-command, keep typing, flip it off. Expect "Reconnecting — input
   buffered", then the whole command lands on reconnect. Nothing typed >15s
   before the reconnect should appear.
4. **Quick actions.** Long-press the hop icon → four sessions, attention first
   → tap one → it should open THAT session. **Test it with the app fully
   closed**: that path was broken until #51 (onChange can't fire for a value
   set before the view exists) and is now verified only by proxy.
5. **Badge.** Let an agent ring a bell with the app closed. A number should
   appear on the icon and clear when you read the session.
6. **Attach claim.** Open a session on the phone that a desktop also has open
   and typed in recently. Text should wrap at PHONE width immediately — if it
   arrives mis-wrapped and only fixes itself once you type, the claim (#21)
   isn't landing.
7. **Links.** In a session that printed a URL, `⋯ → Open link…` should list it
   and open Safari.
8. **Sign out.** `⋯ → Server & account → Sign out` should return to login and
   NOT remember the password; relaunching must not walk back in.
9. **Landscape.** Rotate inside a terminal. Watch for the Dynamic Island or
   home indicator clipping text. Unverified here — simulator rotation needs
   synthetic keystrokes that can hit other apps, so I stopped trying.
10. **Low Data Mode** (Settings → Cellular): live previews should stop
    appearing; the list should still update, just slower.
11. **Reconnect after a real suspend.** Open a shell session (not claude),
    lock the phone for a minute, come back. Three things to watch: history must
    not appear twice, no junk like "35;197;31M" at the prompt, and the screen
    should repaint almost immediately rather than after a pause (the fast paint
    on auto-reconnect, #50). The simulator can't reproduce any of it — it never
    truly suspends.
12. **VoiceOver.** Swipe through the list: each row should read as one sentence
    starting with the name and "wants attention", never raw box-drawing.

## Remaining (needs your call)
- **APNs background delivery**: device-token endpoint + push-on-bell in the
  hop2 daemon. Client work is done; this is the only thing between us and
  "phone buzzes while locked". Needs a greenlight to touch hop2 + coordination
  with Solstice.
- Split panes / wall zoom: deliberately skipped — desktop-shaped.

## Next (Orion)
- [x] Code compiles clean (simulator build green, no API drift)
- [x] **INSTALLED ON DEVICE** — signed with team 5AD7QB9795, bundle
  io.zhoulab.hop.spike. (Wi-Fi install flaky: took ~12 retries through
  DeviceLocked/disconnect; USB cable makes it one-shot.)
- [ ] **AWAITING JAIN'S KEYBOARD VERDICT** — the gate for v1
- [ ] PWA push prototype branch plan (daemon: VAPID + subscribe endpoint + push on
  bellSeq increment; web: manifest + SW). Will be a small separate hop2 commit — 
  coordinating with Solstice before touching shared files.

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
| Hardware keyboard | supported by SwiftTerm (pressesBegan maps ctrl/alt/shift/cmd + arrows); unverified on real hardware |
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
