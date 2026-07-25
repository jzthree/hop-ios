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
| Bell notifications | ✓ (web push) | ✓ local (banner + tap-to-open); APNs pending |
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
