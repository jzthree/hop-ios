# Notes for Solstice (hop2 side) — from Orion, mobile track

Per the boundary: the iOS track doesn't commit to hop2. These are the two
cross-boundary findings, carried to ready-to-apply so the handoff costs one
read. Both were measured, not theorized; evidence lives in hop-ios STATUS.md.

## 1. Scrolling counts as typing in the size election (ready-to-apply)

**Symptom:** any client that scrolls a mouse-tracking app (claude) sends SGR
wheel reports as ordinary `input` messages. `handleInput` bumps
`lastInputAt`, and the size election runs on typing recency — so a phone
*reading* a session becomes the "most recent typist", and a desktop resizing
its window inside the next 60s (`RESIZE_CLAIM_IDLE_MS`) is rejected. Both the
web client and iOS send wheel this way; the fix belongs in the daemon.

**Fix (rooms.ts, `handleInput`):** don't count pure mouse reports as typing.

```ts
  private handleInput(client: ClientState, data: string) {
    if (!this.collabMode && this.controllerId !== client.id) { /* unchanged */ }
    client.lastActive = now();
    // Wheel/mouse reports are reading, not typing: a phone scrolling claude
    // must not steal the size election from someone typing at a desk.
    // SGR mouse reports only — every hop client sends wheel as CSI < b;x;y M/m.
    if (!/^(?:\x1b\[<\d+;\d+;\d+[Mm])+$/.test(data)) {
      client.lastInputAt = now();
    }
    this.pty.write(data);
    this.emit("pty_input", { /* unchanged */ });
  }
```

Regex is anchored and exclusive on purpose: mixed payloads (paste containing
escapes, keystrokes) still count as typing. Only a message that is *nothing
but* wheel reports is exempt.

**Verify:** `hop-ios/tools/probe.mjs <room> hold 90 44 60` from one shell
(types every 1.5s), then send `{type:"input", data:"\x1b[<64;40;12M"}` from a
second client and issue a plain resize from the first within 60s — before the
fix the resize is rejected; after, it wins.

## 2. Preview corruption — status update, scope narrowed

The `getOutputSince` reset-tail bug (tail can start mid-escape-sequence; fix
is the same first-newline trim `boundSnapshotReplay` does) is **still present**
but **does not affect `/api/sessions/preview`**: grid previews render
server-side from persistent terminals. Measured 2026-07-27 across all 20 live
sessions: zero ESC bytes in preview text, all suspected fragments were false
positives ("6m 21s", "250ms"). So the bug's blast radius is only consumers of
`getOutputSince` deltas. Fix remains worthwhile there; the mobile-track
urgency flag is withdrawn.

## 2026-07-28 — The size election: solved client-side, one daemon question left

Context (for Solstice/Jian): the re-entry lottery — a phone returning to a
session rendered whatever size the election last settled on, and every claim
lost to any client that had typed within the idle window. The iOS app grew a
whole apparatus to live with it: adopt+pan, a "take mine" chip, a 5s
foreground retry, fit-on-type, fit-on-touch.

What reading rooms.ts showed: the daemon ALREADY distinguishes deliberate
human claims. `handleResize` honors `user: true` (a deliberate act — wins the
election outright), and the web client sends it on explicit session switches.
The iOS app simply never spoke the flag. As of hop-ios build 230 it does:
attach claims when the app is foreground-active, chip taps, and
touch/keystroke reclaims all carry `user: true`; the background 5s retry
stays recency-based on purpose (a pocket reconnect must not steal a desk's
size). Verified end to end: under a probe holding 100×30 with live typing
recency, a deliberate open took the size instantly (the hold's own socket saw
`active_size 51×49`).

The one daemon-side question that remains, lower stakes now: agent/CLI input
arrives over ordinary WS connections (`{type:"input"}` → `lastInputAt`
bump in handleInput), so a busy agent still counts as an "active typist" for
RECENCY-based claims — it blocks the polite retry, though no longer the
deliberate acts. If that ever matters again, the shape of a fix: let clients
identify as non-interactive at connect (or infer from the API/CLI auth path)
and give their input a much shorter recency window in the election. No
urgency from the mobile track — deliberate claims cover the human cases.

## 2026-07-29 — Wake-flash: closed client-side except the fast-paint window

Marker-traced (three sim runs, foreign 100×30 hold): the wrong-size flash on
wake was (a) the 400ms attach-claim delay — now 0ms on reconnects, the delay
only ever existed for fresh-open keyboard layout — and (b) adopting the
attach rebroadcast's foreign active_size before our deliberate claim's
confirm arrived ~450ms later. Foreign adopts within 3s of a foreground
connect are now DEFERRED 1.2s; the confirm cancels them, so the foreign size
never renders (a lost race still adopts late). What remains is the fast
paint: /api/sessions/screen returns the grid at the PTY's current (foreign)
dims and must be painted at those dims to stay legible, so there's a
~RTT-sized foreign window before the snapshot. Zero-flash needs the daemon:
if attach carried the client's preferred size (with the user flag), the PTY
would reflow before the preview/snapshot are generated. Low urgency — the
window is now small; noting for completeness.

## 2026-07-29 — d1e76ce's unknown-name guard verified from iOS; one residual

Drift-checked the rename/attach fixes against this client. The 404 refusal
for never-existed names is exactly what the iOS classifier already maps to a
permanent "session not found" (verified with a raw upgrade handshake). But
KILLED-and-remembered names still resurrect on attach: create a session,
kill it, attach by its name — the daemon brings it back (probe-proven while
building the gone-test; the resurrected copy was deleted). The unknown-name
guard checks getEffectiveSessionConfig, and a killed session's store/meta
entry survives, so it resolves and re-registers. The iOS client now defends
itself (cache-hearsay attaches verify existence first; reconnects always
did), but any client that attaches by a dead name will still resurrect it.
If the kill path should retire the remembered config (or the attach path
should check hopSessionExists), that's the remaining daemon half.
Also useful to know: /api/sessions/preview serves REMEMBERED content for
killed sessions (list stays clean — no resurrection) and 404s only for
never-existed names.

## 2026-07-31 — Wall previews crop the BOTTOM, and the CSS says so by accident

**Jian's report (desktop):** "the preview terminal is sometimes cut off from
the bottom so I cannot see the bottom few lines." Diagnosed read-only from
this side because it pairs with the phone's wake-size work — see the
relationship note at the end; the fix itself is a hop2 one-liner.

**Where:** `hay/apps/web/src/styles.css`, the pair landed by b7b8aaa
(2026-07-27, "preview → terminal is now a swap in place").

```css
.switcher-preview-scalebox {
  /* Bottom-anchored: the newest terminal lines are the ones worth seeing, so
     content that overflows the tile is cropped from the TOP. Paired with
     transform-origin: bottom left in the tile's rescale. */
  display: flex;
  align-items: flex-end;      /* <- has NO effect on the child below */
  overflow: hidden;
}
.switcher-preview-screen {
  position: absolute;
  top: 0;                     /* <- pins the OLDEST line to the top */
  transform-origin: top left; /* <- the comment above says bottom left */
}
```

An absolutely-positioned child is out of the flex flow, so `align-items:
flex-end` never applies to it. The screen is pinned at `top: 0`, and the
box's `overflow: hidden` therefore crops the **bottom** — the exact opposite
of the block's own documented intent, and the comment's "transform-origin:
bottom left" doesn't match the rule underneath it either. The drift looks
like a rebase artifact of b7b8aaa rather than a decision.

**Why "sometimes":** `ScaledScreen` derives the preview font from box WIDTH
only (`tileFontFor(box.clientWidth)`) and pads rows out to `frame.rows`. A
24-row grid fits the tile's height at that font; a TALL grid does not, and
the overflow — the newest lines — is what gets cut. So the symptom tracks
row count, not content.

**Fix, one of:**
1. `top: 0` → `bottom: 0` and `transform-origin: top left` → `bottom left`
   (this is what the comment already describes), or
2. drop `position: absolute` so the existing `align-items: flex-end` does
   the anchoring it was written for.
Either way the crop moves to the top, where scrollback belongs.

**The relationship to the phone (why this surfaced now):** one PTY, one
size. When a phone claims the grid it elects something tall and narrow —
~49-51 rows against the desk's ~24 — and every wall preview of that session
then overflows its tile and loses its newest lines at the desk. So the
CSS bug is latent until a phone attaches, which is why it reads as "sometimes".
The iOS side is not backing off that claim (a phone that can't fit its own
screen is the worse failure, and hop's election is explicitly deliberate-wins),
but it's worth knowing the desk sees tall grids routinely now.

## 2026-07-31 — A thumbnail is claiming the PTY size with `user: true`

**Jian's report:** "sometimes both hop and hop ios are showing terminal size
matching none of the windows when both attached." Diagnosed from the code;
the mechanism is exact and the fix is one flag.

**The claim.** `SessionSwitcher.tsx`, `claimTileSize()`:

```js
sock.send(JSON.stringify({ type: "resize", cols: dims.cols, rows: dims.rows,
                           claim: "attach", user: true }));
```

Every LiveTile on the wall claims the shared PTY at TILE geometry, and it
carries `user: true`. In `rooms.ts` that flag is decisive:

```js
const isActive = userClaim || client.lastInputAt >= maxInputAt || …;
```

`userClaim` short-circuits the whole recency election — it "wins outright."
The comment above the claim explains the intent ("opening the wall is a
deliberate act"), and for a wall the user just opened that is fair. The
problem is that the claim is re-sent by an AUTOFIT pass — a ResizeObserver /
repaint path that runs with no human behind it — so a thumbnail nobody is
reading repeatedly outranks a window someone IS reading.

**Why it reads as "matching none of the windows":** the winner is often the
TILE. Its geometry (~85 cols, few rows) is neither the desk's focused window
nor the phone's screen, and it is not a window at all — it is a postage stamp
on the wall. The desk's focused client then gets snapped to it by the
lost-election branch, and the phone adopts it too. Everyone renders a grid
that belongs to a thumbnail.

**Two clients both believing they are deliberate** is the whole of it. iOS now
refuses a foreign size while the user is actively looking and re-asserts
(bounded to three, then it adopts and raises the "take mine" chip so a
contested session cannot ping-pong forever). The web tile has its own damping
(1.5s dedupe, 15% tolerance). Both are treating a symptom.

**Suggested fix (hop2, small):** reserve `user: true` for an actual human act
— the wall being opened, or its layout being dragged — and send the autofit
re-claims as ordinary resizes. The daemon's recency election already does the
right thing from there: whoever is actually typing keeps the size, and a tile
that merely repainted does not. If the tile genuinely should never resize a
session someone else is using, the stronger version is to let previews attach
as observers that never claim at all (the daemon has no such concept today —
every socket is a full participant in the election).

Cross-reference: the wall-preview bottom-crop note above has the same origin.
A phone's tall grid overflows the preview box; a tile's short grid starves the
phone. Both are the one-PTY-one-size model meeting screens of different shape.

### Addendum (same day): the client rule changed underneath this

Jian revised the principle: only a KEYSTROKE claims the size; presence,
taps, wakes and timers claim nothing. iOS now has exactly one deliberate
claim (`user: true` on a keystroke); attach and own-fit maintenance are
polite, and when a peer holds the grid the phone renders their shape
scaled to fit rather than contesting it. The refuse/re-assert arbitration
described above is GONE from the client — it was itself a race.

That makes the tile's `user: true` the last unilateral claim in the system.
With the phone no longer contesting, a wall thumbnail now wins essentially
every election it enters, including against a desk window someone is
reading. The suggested fix stands and is now the only thing between here
and a race-free size model: send autofit re-claims as ordinary resizes and
keep `user: true` for a real human act.

## 2026-08-01 — For native passkeys: serve the AASA file, unauthenticated

hop-ios now signs in with the passkey already enrolled in hop web, but the
ceremony runs in a WKWebView because the NATIVE API needs the Associated
Domains entitlement, which needs this file. Measured just now:

    GET https://hop.zhoulab.io/.well-known/apple-app-site-association
    → 200, but content-type text/html — it returns the "Verify Identity"
      login page. The auth wall intercepts the path.

Apple fetches AASA with NO cookies and requires `application/json`, so the
path must bypass authentication entirely (it is public metadata by design —
it names an app, nothing more). Needed:

```
GET /.well-known/apple-app-site-association    (no auth, application/json)
{
  "webcredentials": { "apps": ["5AD7QB9795.io.zhoulab.hop.spike"] }
}
```

`applinks` can be added later if hop ever wants URL handoff into the app;
`webcredentials` alone is what passkeys need. Team 5AD7QB9795, bundle
io.zhoulab.hop.spike. Pairs with the Xcode-account gate on Jian's side —
BOTH are required before the native sheet can replace the web view.
