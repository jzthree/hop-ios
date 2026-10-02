import test from "node:test";
import assert from "node:assert/strict";
import { engagementFrom, engagementScore, normalizeSlots, budgetViolations, enforceBudgets, applyTightened, trimWords, wordCount, BUDGET } from "./digest.mjs";

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

test("slots: an edition without them maps from urgency; also/non-decide items shed what they must not carry", () => {
  const d = normalizeSlots({ summary: "s", items: [
    { session: "a", headline: "h", why: "w", urgency: "needs-you" },
    { session: "b", headline: "h", why: "w", slot: "also", recommendation: "x", replies: ["y"] },
    { session: "c", headline: "h", why: "w", slot: "done", recommendation: "x" },
    { session: "d", headline: "h", slot: "decide", replies: ["Approve", "", "Hold", "Rerun", "Extra"] }
  ] });
  assert.equal(d.items[0].slot, "decide"); assert.equal(d.items[0].urgency, "needs-you");
  assert.equal(d.items[1].urgency, "fyi"); assert.equal(d.items[1].why, undefined); assert.equal(d.items[1].recommendation, undefined);
  assert.equal(d.items[2].recommendation, undefined);
  assert.deepEqual(d.items[3].replies, ["Approve", "Hold", "Rerun"]);
});

test("budgets: violations are listed with their budget, a tighten pass applies by path, the rest is cut at a word", () => {
  const long = Array.from({ length: 40 }, (_, i) => `w${i}`).join(" ");
  const d = normalizeSlots({ summary: long, items: [
    { session: "a", slot: "decide", headline: "one two three four five six seven eight nine ten", why: long, recommendation: long },
    { session: "b", slot: "done", headline: "fine", why: Array.from({ length: 16 }, () => "x").join(" ") }
  ] });
  const over = budgetViolations(d);
  assert.deepEqual(over.map((o) => o.path), ["summary", "items[0].headline", "items[0].why", "items[0].recommendation", "items[1].why"]);
  assert.equal(over[0].budget, BUDGET.summary); assert.equal(over[4].budget, BUDGET.whyDone);
  applyTightened(d, { summary: "Nothing needs you this hour.", "items[0].headline": "Approve the profile", "items[9].why": "ignored" });
  assert.equal(d.summary, "Nothing needs you this hour.");
  assert.equal(d.items[0].headline, "Approve the profile");
  enforceBudgets(d);
  assert.ok(wordCount(d.items[0].why) <= BUDGET.whyDecide);
  assert.ok(wordCount(d.items[1].why) <= BUDGET.whyDone);
  assert.ok(wordCount(d.items[0].recommendation) <= BUDGET.recommendation);
  assert.equal(budgetViolations(d).length, 0);
});

test("trimWords keeps a whole sentence when one fits, else cuts with an ellipsis", () => {
  assert.equal(trimWords("The run finished. It beat the baseline by a hair and the rest is noise", 8), "The run finished.");
  assert.equal(trimWords("one two three four five", 3), "one two three…");
  assert.equal(trimWords("short", 3), "short");
});
