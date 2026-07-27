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
