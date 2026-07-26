# APNs: what's left, and what it would touch

Written so the decision is a yes/no rather than an investigation. **Nothing in
hop2 has been changed** — that needs Jian's greenlight and coordination with
Solstice. This is the shape of the work if it's wanted.

## Why it matters more than it looks

Local notifications only fire while the app is running. Everything else that
could wake a phone is best-effort:

- **Background refresh** is the fallback, and it has never been observed
  working. It is refused outright in the simulator, and the device has never
  reported a grant. `Copy diagnostics` now answers this in one line
  (`background: … / never ran`), so the first checklist run settles whether
  bells reach a pocket at all today.
- If that line says `never ran` after a normal day, then **the app currently
  tells you an agent is waiting only while you are already looking at it** —
  which is most of the value gone.

## The client half is done

| Piece | State |
|---|---|
| Explicit App ID, Push capability | done |
| `aps-environment` entitlement in the signed app | done — `development` for local installs, `production` for TestFlight |
| Token registration (`registerForRemoteNotifications`) | done, token shown in Copy diagnostics |
| Notification category + Reply action | done — shared with local bells, so a push gets the same reply field |
| `bellSeq` coercion for push payloads | done (#111) — a number from APNs arrives as NSNumber, and `as? Int` would have silently dropped it, leaving the session's dot and badge in place after you replied |

So a push that arrives with the right payload works today, with no further iOS
changes.

## The daemon half

Two endpoints' worth of work, plus a send path.

**1. Register a device token.**

```
POST /api/push/register   { token, bundleId, environment }   → { ok }
POST /api/push/unregister { token }                          → { ok }
```

Same auth as every other endpoint (the tunnel session). Store per-token:
`token`, `environment` (`development` | `production`), `lastSeen`. A device
that re-registers replaces its row — tokens rotate.

**2. Send on bell.**

hop already counts bells into `bellSeq` (`rooms.ts`). Where that increments,
push to every registered token:

```json
{
  "aps": {
    "alert": { "title": "<session name>", "body": "<last line of output>" },
    "sound": "default",
    "interruption-level": "time-sensitive",
    "thread-id": "<internalName>",
    "category": "HOP_SESSION_BELL"
  },
  "session": "<internalName>",
  "bellSeq": 42
}
```

- `category` and the two custom keys are what make the reply action work —
  they are exactly what the local path already sets.
- **`apns-collapse-id: <internalName>`** so a session that rings five times
  replaces its own notification instead of stacking five.
- `apns-topic` is the bundle ID; `apns-push-type: alert`.
- Drop a token permanently on `410 Unregistered`. That is the only cleanup
  APNs asks for, and skipping it means sending to dead devices forever.

**Auth**: a `.p8` key from the Apple developer account (key ID + team ID),
signed into a JWT that is valid for an hour and reused — not minted per push,
which Apple rate-limits. `scripts/asc.py` in this repo already does ES256 JWT
signing with `openssl` for App Store Connect; the same shape works here.

## The decision that has to be made first

**Which environment?** They are different APNs hosts and different tokens, and
a token from one is rejected by the other.

- `api.sandbox.push.apple.com` — for locally-installed builds. Today's
  `make install` is deliberately `development` for exactly this reason.
- `api.push.apple.com` — for TestFlight and the App Store.

The daemon should store the environment alongside the token and pick the host
per token, rather than assuming. Otherwise the first TestFlight build silently
stops receiving pushes, and the failure looks exactly like "no agent rang".

## Size

Roughly: 60 lines for the endpoints and store, 40 for the JWT and send, 10 at
the bell site, plus wherever hop keeps its secrets for the `.p8`. The client
needs nothing. The risky part is not the code — it is that a mistake here is
silent, so it wants the same treatment the client got: log what was sent, log
what APNs answered, and make `never sent` visible rather than assumed.

## What I would want to see before calling it done

1. A bell rung on a scratch session with the app **force-quit** raises a
   banner.
2. Replying from that banner lands the line in the session and clears the dot
   — the path #111 fixed, which no test can reach until a real push exists.
3. `410 Unregistered` on a stale token removes it, verified by deleting the
   app and ringing again.
