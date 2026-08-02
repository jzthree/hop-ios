#!/usr/bin/env node
// The digest: "what should I pay attention to", written by an agent that sees
// the whole fleet, for a phone that is about to be picked up.
//
// Runs on the HOST, not the phone: the host already has the screens, the bell
// history and the Claude subscription, so the phone stays cheap and a 07:00
// digest does not depend on the phone being awake.
//
// Deliberately NOT prescriptive about the result, by request: "i dont want to
// dictate 8 items or be too specific — let the agent decide and give more
// autonomy to the agent." So the prompt states the JOB and the constraints
// that are real (one screen, tappable, priority-ordered) and leaves how many
// items, how to group them and what matters entirely to the agent.
//
// Input is cheap by construction: the last screen we already have per session
// plus its tagline and attention state. No scrollback, ever.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";

const state = JSON.parse(
  fs.readFileSync(path.join(os.homedir(), ".hop2/.tunnel-state"), "utf8"));
const BASE = `http://127.0.0.1:${state.port}`;
const COOKIE = `tunnel_session=${state.sessionSecret}`;
const OUT = process.argv[2] || "/tmp/hop-digest.json";
// Opus, at the maintainer's word: "lag is not a problem, user will not see it until
// done." The digest is generated on a schedule and read later, so judgement
// is the only axis that matters — nobody is waiting on the spinner.
const MODEL = process.env.DIGEST_MODEL || "opus";

const api = async (p, init = {}) => {
  const r = await fetch(BASE + p, {
    ...init,
    headers: { Cookie: COOKIE, "Content-Type": "application/json", ...(init.headers || {}) }
  });
  if (!r.ok) throw new Error(`${p} -> ${r.status}`);
  return r.json();
};

/// The screen we already cache, trimmed to its meaningful tail. A digest is
/// about what is happening NOW, and the tail is where that lives.
const tail = (text, lines = 18) =>
  (text || "").split("\n").filter((l) => l.trim()).slice(-lines).join("\n");

const run = (bin, args, input) =>
  new Promise((resolve, reject) => {
    const p = execFile(bin, args, { maxBuffer: 32 * 1024 * 1024, timeout: 240000 },
      (err, stdout) => (err ? reject(err) : resolve(stdout)));
    if (input) { p.stdin.write(input); p.stdin.end(); }
  });

const main = async () => {
  const list = await api("/api/sessions");
  const sessions = (list.sessions || list).filter(
    (s) => s.live && s.type !== "port" && !s.parked && !s.archived);

  const seen = [];
  for (const s of sessions) {
    let screen = "";
    try {
      // GET with ?name=, not a POST body — the app's own fetchPreview is the
      // reference. A POST 404s, and the digest then reports "all quiet"
      // because every screen came back empty (caught on the first run).
      const pv = await api(`/api/sessions/preview?name=${encodeURIComponent(s.internalName)}`);
      screen = tail(pv.text || "");
    } catch { /* a session that will not preview is not worth failing over */ }
    seen.push({
      session: s.internalName,
      name: s.displayName || s.name,
      about: s.tagline || "",
      wants_you: !!s.attention,
      idle_seconds: s.lastActivityAt
        ? Math.round(Date.now() / 1000 - s.lastActivityAt) : null,
      screen
    });
  }

  const prompt = `You are the user's co-scientist, not a status board.

They run a lab through these terminals: model training and evaluation,
reproductions, data pipelines, and the software that carries them. Some
sessions are their own work; most are agents working for them. Below is every live
session — what it is for, whether it rang for attention, how long it has been
idle, and the tail of its screen right now.

Write the briefing they actually need before they pick up their phone. Lead
with what they would most regret not knowing.

Think like a colleague who has read all of it and understands the science, not
like a reporter listing which windows have unread output. That means:
- A RESULT that changed, was retracted, or contradicts something they were told
  earlier is more important than a process that is merely waiting.
- Say what a finding MEANS and what it puts at risk downstream — if a
  reproduction failed, what conclusions rest on it.
- Notice what is quietly wrong: experiments that were never actually launched,
  runs that stopped writing, compute or tokens being spent on something idle,
  a decision two sessions are each waiting on the other for.
- Connect across sessions when they bear on each other. Nobody else can see
  the whole fleet at once; that is your advantage, so use it.
- Be specific and quantitative where the screen gives you numbers. "auPRC fell
  on the held-out split" beats "results look off".

You decide how many items, how to rank or group them, and what deserves saying
at all — you are the judge of what matters, not a summariser of everything.
Leave out what they do not need. If nothing needs them, say so plainly and
briefly, and say what you checked.

Two real constraints. It must fit one phone screen without scrolling — so be
informative per line, not longer. And each item must name exactly one session,
because each becomes a button they tap to open it.

Reply with ONLY a JSON object:
{"generated_at":"<ISO8601>","summary":"<the one thing to know, in a sentence>",
 "items":[{"session":"<internalName exactly as given>",
           "headline":"<what happened, concretely>",
           "why":"<what it means or puts at risk, one sentence>",
           "urgency":"needs-you"|"blocked"|"finished"|"fyi"}]}

Sessions:
${JSON.stringify(seen, null, 1)}`;

  const raw = await run("claude", ["-p", "--model", MODEL], prompt);
  const json = raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1);
  const digest = JSON.parse(json);
  digest.model = MODEL;
  digest.generated_at = digest.generated_at || new Date().toISOString();
  fs.writeFileSync(OUT, JSON.stringify(digest, null, 1));
  console.log(`${OUT}: ${digest.items?.length ?? 0} items (${MODEL})`);
};

main().catch((e) => { console.error(String(e)); process.exit(1); });
