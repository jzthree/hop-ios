# hop-ios

A native iOS client for [hop](https://github.com/jzthree/hop) — your terminals
and agent sessions, on the phone, over your existing Cloudflare tunnel.

It exists because the web client hit iOS's ceiling: Safari can't give a real
keyboard (dictation, autocorrect, key repeat), can't do haptics since iOS 17.4,
and can't notify you when an agent wants attention. This app can.

Standalone by design: it consumes hop's public HTTP + WebSocket API and needs
**no changes to hop** to run. If it stops earning its keep, delete the repo.

## Quick start

```bash
brew install xcodegen          # once
make test                      # unit suite in the simulator
make uitest                    # real gestures via XCUITest (slow, ~4 min/test)
make install                   # signed build -> connected iPhone
```

Then in the app: enter your hop URL (e.g. `hop.zhoulab.io` — the scheme is
optional), your hop password and a 6-digit authenticator code. The session
cookie lasts 7 days; the password can be remembered in the keychain so
re-login is one code.

Requirements: Xcode 26+, an Apple ID signed in to Xcode (Settings → Accounts),
Developer Mode enabled on the phone, and a hop daemon reachable at that URL.

## What it does

- **Account** — server address, session count, sign out (drops the cookie, the
  saved password, the badge and the quick actions); changing servers starts
  there.
- **Session list** — attention-first, with taglines, working directory, running
  app, relative time, and a 3-line live preview of each session's screen.
  Filter by name, cwd, app or tagline — or search the OUTPUT of every session
  at once (hop scans server-side and returns snippets). Scope to You / Agents
  / All. Create, rename, kill, and toggle
  agent (MCP) access.
- **Fast opens** — the session's current screen paints immediately over HTTP
  while the (much larger) WebSocket snapshot downloads.
- **Terminal** — SwiftTerm over hop's WebSocket, with the native keyboard plus
  a key bar (esc, tab, sticky ctrl, alt/meta, ^C, arrows, `| / - ~`, PgUp/PgDn,
  paste). Find in scrollback, copy screen/all, font size (menu or pinch),
  light/dark, jump-to-live, and session switching from the title.
- **Attention** — a session that rings the terminal bell raises a dot, a
  haptic, an app-icon badge, and (opt-in) a local notification that opens
  straight to it. Long-press the icon for the four sessions most likely to want
  you. Never for the session you're currently watching.
- **Good pocket citizen** — polling follows the network: 5s on Wi-Fi, backed
  off on cellular, and Low Data Mode drops live previews entirely.
- **Resilience** — input typed during an outage is buffered and replayed
  (15s cap, so nothing stale lands late); auto-reconnect on foreground and
  after drops with backoff;
  a network blip never logs you out; unreachable servers fail fast with a
  readable error instead of hanging.

## Layout

| File | Role |
|------|------|
| `HopSpikeApp.swift` | app entry, theme, login screen |
| `AppModel.swift` | server URL/auth, session list + previews, session CRUD |
| `HayClient.swift` | hop's room WebSocket protocol (snapshot/output/presence/collab) |
| `TerminalScreen.swift` | SwiftTerm host, key bar, menus, control actions |
| `SessionsView.swift` | session list, scope/filter, empty states |
| `Notifications.swift` | bell → local notification, tap-to-open |
| `Keychain.swift` | remembered password (device-only, never the TOTP secret) |
| `NetworkConditions.swift` | NWPathMonitor: poll cadence, offline detection |
| `SessionFilter.swift` | pure list shaping (unit-tested) |
| `Links.swift` | URLs off the screen, wrap-aware (unit-tested) |
| `QuickActions.swift` | Home Screen shortcuts + the scene delegate they need |
| `AccountView.swift` | server info, sign out, version |

## Talking to hop

- Auth: `POST /api/login` with `{password, totp}` sets the `tunnel_session`
  cookie. The daemon also accepts `Authorization: Bearer <secret>` or
  `?token=<secret>` — that's how the simulator skips TOTP in development.
- Sessions: `GET /api/sessions`; previews: `GET /api/sessions/preview?name=`;
  mutations: `POST /api/sessions{,/rename,/delete,/agent-permission}`.
- Terminal: `wss://<host>/ws?room=<internalName>&name=&cols=&rows=`.
- Size: hop elects the shared PTY size by typing recency. A plain `resize`
  needs every peer input-idle 60s; the first fit after attaching must send
  `claim: "attach"` (2.5s) or the phone renders at a desktop peer's width.

Two iOS traps worth remembering, both cost real debugging time:
1. `Cookie` is a **reserved** URLSession header — a manually set one is dropped
   unless `httpShouldHandleCookies = false`, and URLSession's own jar skips
   `Secure` cookies on `wss://`. Miss both and the upgrade 401s (Cloudflare
   reports that as 502).
2. `URLSessionWebSocketTask` caps messages at **1 MB** by default; hop's join
   snapshot is up to 1.5 MB, so any session with real scrollback dies right
   after a successful upgrade unless `maximumMessageSize` is raised.

## Development

`make sim` runs it in the simulator against your live daemon (auth via the
daemon's own token, no TOTP). `make sim OPEN=Solstice` opens a session
directly. `make shot` grabs a screenshot. `make sim GROUP=1 SCOPE=all
SHEET=account` lands on a specific state — a screenshot is the only way to
review UI that a unit test can't see. Dev-only env vars: `HOP_DEV_TOKEN`,
`HOP_DEV_COOKIE`, `HOP_DEV_OPEN`, `HOP_DEV_SCOPE`, `HOP_DEV_NOTIFY`,
`HOP_DEV_GROUP`, `HOP_DEV_SHEET`, `HOP_DEV_FILTER`, `HOP_DEV_OFFLINE`.

### Reading the app's diagnostics

The app logs the handful of numbers that explain its behaviour, under
subsystem `io.zhoulab.hop.spike`. Note `--info`: these are info-level and are
invisible without it.

Simulator:

```bash
xcrun simctl spawn <sim> log show --last 60s --info \
  --predicate 'subsystem == "io.zhoulab.hop.spike"'
```

On the phone, `log collect --device-udid` needs admin, so use **Console.app**:
open it, pick the iPhone in the sidebar, Start streaming, and put
`io.zhoulab.hop.spike` in the search box (Action → Include Info Messages).

| Line | What it tells you |
|------|-------------------|
| `attach claim 51x26 for X` | the phone claimed the shared PTY size — if absent, the terminal will be wrapped at some other client's width |
| `snapshot 2447 KB after 96 ms` | what opening that session cost on the wire, and how long the server took |
| `scrollback reachable N lines` | how much history find and copy-all can actually see (26 = one screen; TUI apps have no scrollback) |
| `published N quick actions` | Home Screen shortcuts were refreshed — the only evidence, since SpringBoard owns them |
| `background refresh finished, success=` | a pocket bell-poll ran; silence here means iOS stopped granting slots |
| `unhandled server message X` | hop added a protocol message this client ignores |
| `server rejected a message: …` | this client sent something hop couldn't parse — input may be silently broken |

`tools/lan-bridge.mjs` exposes the local hay-host to the LAN for testing
without a tunnel — it's LAN-open while running, so stop it when done.

Coordination notes and the running change log live in `STATUS.md`.
