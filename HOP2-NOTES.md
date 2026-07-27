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
