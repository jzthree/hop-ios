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

## Next (Orion)
- [x] Code compiles clean (simulator build green, no API drift)
- [x] **INSTALLED ON DEVICE** — signed with team 5AD7QB9795, bundle
  io.zhoulab.hop.spike. (Wi-Fi install flaky: took ~12 retries through
  DeviceLocked/disconnect; USB cable makes it one-shot.)
- [ ] **AWAITING JAIN'S KEYBOARD VERDICT** — the gate for v1
- [ ] PWA push prototype branch plan (daemon: VAPID + subscribe endpoint + push on
  bellSeq increment; web: manifest + SW). Will be a small separate hop2 commit — 
  coordinating with Solstice before touching shared files.
