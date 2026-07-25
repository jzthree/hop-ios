# hop-ios STATUS — owned by Orion (mobile track)

Division of labor: **Orion** (this repo, mobile) · **Solstice** (hop2, desktop).
Solstice: read-only for you; leave notes for me in hop2 commits or tell Jian.

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
   → tap one → it should open THAT session, cold launch included. The publish
   is log-verified; the tap-through is not.
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
11. **VoiceOver.** Swipe through the list: each row should read as one sentence
    starting with the name and "wants attention", never raw box-drawing.

## Spike test script (once installed)
1. On Mac: `node ~/Code/hop-ios/tools/lan-bridge.mjs` → note the ws:// URL.
2. On iPhone: HopSpike → paste URL, session e.g. `Solstice` → Attach.
3. Judge: keyboard feel (real keys, autocorrect/dictation, key repeat),
   scroll physics, latency vs the web client. That verdict gates v1.

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

## Web-mobile parity matrix (audited from hay/apps/web, 2026-07-25)
| Feature | web mobile | iOS |
|---|---|---|
| Attach / live terminal | ✓ | ✓ |
| Session list, attention-first | ✓ | ✓ |
| Taglines / cwd / app badge / relative time | ✓ | ✓ |
| Filter sessions | ✓ | ✓ (searchable) |
| Origin scope user/agent/all | ✓ | ✓ (segmented) |
| Create / rename / kill session | ✓ | ✓ (+ button, swipe actions) |
| Find in scrollback | ✓ | ✓ (menu → Find) |
| Copy screen / copy all | ✓ | ✓ (menu) |
| Font size | ✓ | ✓ (menu ± ) |
| Light/dark terminal | ✓ | ✓ (menu toggle) |
| Reconnect in place | ✓ | ✓ (menu) |
| Accessory keys esc/tab/ctrl/alt/arrows | ✓ | ✓ + ^C, \| / - ~, PgUp/PgDn, paste, dismiss |
| Native keyboard (dictation/autocorrect) | via KB button | ✓ always (this is the native win) |
| Bell → haptic | ✗ (iOS Safari has no haptics) | ✓ |
| **Still missing on iOS** | | |
| Live session previews | ✓ (hero tiles) | ✓ (3-line live screen per row) |
| Presence / take-release control | ✓ | ✓ (viewer count + list, lock/unlock typing, take/release) |
| Bell notifications | ✓ (web push) | ✓ local + background refresh; APNs pending for instant/closed |
| Split/secondary pane, wall zoom | ✓ | ✗ (desktop-shaped) |
| Agent-permission toggle | ✓ | ✓ (long-press a session) |
| Passkey / share link | ✓ | ✗ (low value on phone) |
| Saved password (keychain) | ✗ | ✓ (device-only; TOTP still required) |

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
