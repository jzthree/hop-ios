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

*(top rewritten at iteration 112 — everything above the parity matrix had gone
stale: it still said twenty commits were waiting on an unreachable phone.)*

**Installed and current.** The phone builds and installs in one shot again, and
every functional commit through iteration 111 is on it.

**Waiting on you, in order of what unblocks most:**
1. **The device checklist below.** Most of it is ordinary use — but four items
   can ONLY be answered with a phone in hand, and two of those decide whether
   features that look finished actually work at all.
2. **App Store Connect → Apps → + → New App**, bundle ID `io.zhoulab.hop.spike`
   (already registered, appears in the dropdown). Then
   `make testflight ISSUER=254072af-7f14-4065-acd8-d09fe4924553` uploads, and
   the phone installs over 5G — no more "is the phone on this network".
3. **The APNs decision** (below): a daemon endpoint and a send-on-bell path.
   Apple's half is done — explicit App ID, Push enabled, entitlement in the
   signed app, client obtaining and displaying a token.

**Open questions for you, one line each:**
- Should `archived` sessions (stopped but resumable) be marked as stopped in
  the list?
- Web previews now render the WHOLE screen at grid geometry, scaled to fit
  (hop2 b7b8aaa, 7/27). Should phone rows follow suit, or stay 3-line text?
  Cost note before choosing: scaled-screen rows are heavier per render and the
  phone polls up to 8 previews on a cellular budget — the answer isn't
  automatically "match the web". They are parsed and hidden with
parked ones today; opening one resumes it transparently.

**Handed over, not done here:** the preview-corruption bug in hop
(`getOutputSince`'s reset tail can start mid-escape-sequence — see Reference).
It affects the web switcher and iOS equally; the fix is a few lines of shared
hop2 code.

## Device checklist ⚠ ONLY YOU CAN DO THESE

Ordered by what is most likely to be wrong and what it costs if it is. The
first four are the ones a simulator provably cannot answer.

If something looks wrong, the app says why in the log: **Console.app → your
iPhone → search `io.zhoulab.hop.spike`** (Action → Include Info Messages).
README has a table of what each line means.

1. **Does the coast feel right?** Flick a claude session. The glide should
   decay over roughly a couple of seconds, like any iOS scroll view. It is
   built on UIScrollView's own deceleration rate and made frame-rate
   independent specifically for your 120Hz screen (#103) — but the simulator
   is 60Hz, so this number has never been felt on the hardware it was written
   for. If it feels too fast or too short, that is a real finding.
2. **Has iOS ever granted a background slot?** `⋯ → Server & account → Copy
   diagnostics` → paste it here. The `background:` line reads
   `requested … / ran …` or `never ran`. Background refresh is what lets a bell
   reach you with the app closed, it has never once been observed working, and
   the simulator refuses BGTaskScheduler outright (#107). If it says
   `never ran` after a day of normal use, APNs stops being a nice-to-have.
3. **Hardware ctrl combos**, if you have a keyboard case. ctrl+C should
   interrupt, not type a `c`. Plain typing and arrows are verified; modifiers
   are not, because XCUITest delivers `mods=0` (#104).
4. **Keyboard feel — the thesis the app rests on.** Type a real command with
   dictation and autocorrect. If this doesn't beat the web client, nothing else
   in this repo matters.
5. **Reconnect after a real suspend.** Open a shell session (not claude), lock
   the phone for a minute, come back. History must not appear twice, no junk
   like "35;197;31M" at the prompt, and the screen should repaint immediately
   rather than after a pause. The simulator never truly suspends.
6. **Walk out of wifi.** With a session open, leave the house on 5G. The
   terminal should come back on its own within a second or two rather than
   sitting dead for the backoff (#98) — that path is wired and logged here but
   only a phone that moves can prove it.
7. **Reply from the notification.** Long-press a bell notification, type a
   reply, Send. **Do this first on a SHELL session, not an agent** — a stray
   line in an agent session could approve something.
8. **Quick actions with the app fully closed.** Long-press the hop icon → four
   sessions, attention first → tap one → it should open THAT session.
9. **Badge.** Let an agent ring with the app closed: a number appears and
   clears when you read the session.
10. **Attach claim.** Open a session a desktop also has open and typed in
    recently. Text should wrap at PHONE width immediately.
11. **Low Data Mode** (Settings → Cellular): live previews stop appearing; the
    list still updates, slower.
12. **Landscape, sign out, links, VoiceOver.** Rotation hiding chrome, sign-out
    forgetting the password, `⋯ → Open link…`, and each row reading as one
    sentence starting with the name.

## Decisions that are yours

- **APNs background delivery**: device-token endpoint + push-on-bell in the
  hop2 daemon. Client work is done — including the NSNumber coercion that path
  will need (#111). This is the only thing between here and "phone buzzes while
  locked". Needs a greenlight to touch hop2 and coordination with Solstice.
  **`APNS-PLAN.md` now spells out the whole shape** — endpoints, payload,
  collapse-id, the `410 Unregistered` cleanup, and the one decision that has to
  come first (sandbox vs production hosts, which is why local installs are
  pinned to `development`). Roughly 110 lines of daemon code; nothing further
  on the client. Written so the answer can be yes or no rather than an
  investigation.
- **Archived sessions**: marked as stopped in the list, or left transparent?
- Split panes / wall zoom: deliberately skipped — desktop-shaped.

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
