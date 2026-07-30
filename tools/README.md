# tools/ — the verification harness

`upkeep.sh` runs the whole maintenance tick in one command: upstream drift,
both suites, strict concurrency, TSan, and what build the device actually has.

`probe.mjs` drives a hop session from outside the app: real bells, size
elections, known fixtures. Its header documents the actions. Everything here
sends REAL input — use scratch sessions.

## The patterns that produce trustworthy evidence

- **In-test screenshots.** Racing `simctl io screenshot` against a test's
  teardown loses. Tests write their own: `XCUIScreen.main.screenshot()
  .pngRepresentation.write(to:)` at the exact moment that matters.
- **Marker-file choreography.** When the outside world must act mid-test (ring
  a bell, kill a session), the test writes a marker file at the ready moment
  and sleeps; the shell polls for the marker, acts, and the test resumes.
- **Controls, always.** Measure the idle state before the treatment. Both
  uncontrolled measurements this project made pointed at MORE work that wasn't
  needed (see STATUS #89).
- **Discriminators.** A test that cannot fail proves nothing: run the old code
  against the new test once and watch it fail for the stated reason.

## The traps (each cost real time; war stories in STATUS.md)

| Trap | Truth |
|---|---|
| `log stream` without `--level info` | drops every info-level line silently |
| `simctl pbpaste` | lies; read the copied length from the app's own log |
| XCUITest `typeKey(_:modifierFlags:)` | delivers `mods=0` — ctrl combos untestable |
| XCUITest hold on the system keyboard | never triggers the keyboard's own repeat timer |
| Simulator rotation | can wedge after many runs; reboot the sim before blaming the app |
| `staticTexts` queries | SwiftUI collapses Text into parent Buttons; dump `debugDescription` and query what is really there |
| Named session fixtures | fleets churn; a vanished fixture reads as a feature regression |
| `make x 2>&1 \| grep …` | the pipeline's exit code is grep's — failures ship |
| Regex-editing probe scripts | substitutions fail silently; write whole files |
| A simulator measurement of keyboard/push/background behaviour | is evidence about the simulator |
| A metric that improves without a cause | is a check that stopped running (incremental builds re-emit no warnings; `make strict` cleans first for this reason) |
| `make test \| grep` runs the whole chain on FAILED | grep exits 0 on match, so `&& next-step` proceeds past a red suite | capture make's own exit status before grepping the log |
| "Failed to create a bundle instance … containermanagerd/Dead" | sim container churn — ZERO tests ran, which is not the same as tests failing | rerun; if the rerun is green with full counts, the suite was never red |
| test counts quoted from memory drift upward | "N tests" in STATUS was base + new-tests-written, not the meter | state counts only from the run's own Executed/passed line |
| `simctl openurl` exits 0 and silently drops custom-scheme URLs | cold fire doesn't even launch the app; reinstall doesn't fix it | verify on DEVICE: `devicectl device process launch --payload-url` — even a locked phone routes it, and a WS attach is the daemon-side observable |
| `simctl spawn log` shows nothing for os.Logger lines that provably ran | logd predicates in the sim lie | instrument with a marker FILE in the app container and read it via get_app_container |
| echoing `$?` is not GATING on it | iteration 172 echoed "ui exit: 2" and the chain committed + deployed anyway | `EXIT=$?; [ $EXIT -ne 0 ] && stop` — the ship chain must die on red, not narrate it |
| a diagnostic marker sliced prefix(12) while the code fetched prefix(16) | the instrument reported zero coverage for names the code was actually fetching | a marker must log the SAME expression the code executes, never a copy of it |
| the XCUITest runner reads UIPasteboard as empty no matter what the app wrote | iOS 16 background-paste privacy silently denies reads from a process that is never foreground — the runner | verify copy actions via a DEBUG marker file (HOP_COPY_MARKER pattern), never by reading the pasteboard from the runner |
| the fixture's display name churns daemon-side (Meridian->nebula, third incident) and every churn reads as a scroll regression | display names are ungated writes; internal names are stable | make uitest resolves TEST_RUNNER_HOP_E2E_FIXTURE from FIXTURE_INTERNAL via /api/sessions at suite start — repoint FIXTURE_INTERNAL, never the display string |
| the share sheet is visibly on screen but app.buttons["Copy"] matches nothing (and so does springboard) | its actions are CELLS — actionGroupCell with label "Copy" — in the APP's own tree, not buttons anywhere | query app.cells by label predicate; dump app.debugDescription with the sheet up before guessing hosts |
| the hop-keyboard suite fails differently every run after a wedge | the board preference is UserDefaults-sticky; an aborted run leaves it ON, breaking every keys[]-based test after it | the toggle test self-corrects (tap again if letters don't appear) and ends on the system keyboard; if keys[] tests all fail at once, suspect the sticky board first |


## The history-anchor probe (rerun recipe)

The anchor (scrolled-up view holding position under streaming output) needs a
TICKING fixture, so its probe is a temp test, not a permanent one:

1. `curl -X POST …/api/sessions {"name":"scratch-anchor"}` then
   `node tools/probe.mjs scratch-anchor type 'for i in $(seq 1 2000); do echo tick $i $(date +%T); sleep 1; done\n'`
2. Temp test: open scratch-anchor, three drags into history, screenshot,
   sleep 12, screenshot, assert the Live pill still exists; Bash pixel-diffs
   the two shots' text region (identical = anchored).
3. Kill the scratch. Two regressions this catches: the feed pin yanking the
   reader to live, and hasHistory misreporting (the Live pill dying).
