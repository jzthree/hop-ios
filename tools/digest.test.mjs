import test from "node:test";
import assert from "node:assert/strict";
import { engagementFrom, engagementScore } from "./digest.mjs";

const H = 3600 * 1000;

test("turns in a window are the counter's rise since the window opened; opens count seen-stamp advances", () => {
  const now = 100 * H;
  const samples = [
    { t: now - 30 * H, turns: 10, seenAt: 1 },   // before the 24h window: the baseline
    { t: now - 20 * H, turns: 14, seenAt: 1 },
    { t: now - 10 * H, turns: 20, seenAt: 5 },   // opened once
    { t: now - 1 * H,  turns: 25, seenAt: 9 }    // opened again
  ];
  assert.deepEqual(engagementFrom(samples, now, 24 * H), { turns: 15, opens: 2 });
  // A session younger than the window under-counts rather than over-counts.
  assert.deepEqual(engagementFrom(samples.slice(1), now, 24 * H), { turns: 11, opens: 2 });
  assert.deepEqual(engagementFrom([], now, 24 * H), { turns: 0, opens: 0 });
});

test("today's turns outrank the week's, and a recent last turn breaks ties", () => {
  const now = 100 * H;
  const busyToday = engagementScore({ turns: 12, opens: 3 }, { turns: 12, opens: 3 }, now - 1 * H, now);
  const busyLastWeek = engagementScore({ turns: 0, opens: 0 }, { turns: 40, opens: 6 }, now - 5 * 24 * H, now);
  assert.ok(busyToday > busyLastWeek);
  const a = engagementScore({ turns: 2, opens: 1 }, { turns: 2, opens: 1 }, now - 1 * H, now);
  const b = engagementScore({ turns: 2, opens: 1 }, { turns: 2, opens: 1 }, now - 20 * H, now);
  assert.ok(a > b);
});
