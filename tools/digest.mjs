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
import crypto from "node:crypto";

const state = JSON.parse(
  fs.readFileSync(path.join(os.homedir(), ".hop2/.tunnel-state"), "utf8"));
const BASE = `http://127.0.0.1:${state.port}`;
const COOKIE = `tunnel_session=${state.sessionSecret}`;
// WHERE IT LANDS: the daemon serves files under /assets/ from whatever
// HAY_WEB_DIR resolves to, behind the same session cookie the app already
// holds — so the digest needs no new endpoint and no hop2 change at all.
// Two candidates, in the daemon's own precedence order: a local dev build
// wins over the packaged one (verified live — writing to hay-web/assets 404s
// while the dev dist is present). Both are already gitignored.
const servedAssets = () => {
  const roots = [
    path.join(os.homedir(), "Code/hop2/hay/apps/web/dist/assets"),
    path.join(os.homedir(), "Code/hop2/hay-web/assets")
  ];
  return roots.find((d) => fs.existsSync(d)) || null;
};
// Write to EVERY existing candidate root, not the first: the daemon rebuilds
// the dev dist on web changes and the rebuild DELETES whatever was in it —
// the 17:06 digest was simply gone by evening (log said written, file absent).
// Writing to both means a rebuild costs at most one slot, not the day.
const OUTS = process.argv[2] ? [process.argv[2]] : (() => {
  const roots = [
    path.join(os.homedir(), "Code/hop2/hay/apps/web/dist/assets"),
    path.join(os.homedir(), "Code/hop2/hay-web/assets")
  ].filter((d) => fs.existsSync(d));
  return roots.length ? roots.map((d) => path.join(d, "digest.json"))
                      : ["/tmp/hop-digest.json"];
})();
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

// WHAT IS ACTUALLY IN THE INPUT BOX.
//
// Claude Code renders an autocomplete SUGGESTION inside its composer, styled
// dim, with the cursor still parked at the start of the line. A human reads
// that instantly — wrong shade, cursor in the wrong place — but the plain
// text preview the digest reads flattens both signals away, so edition after
// edition reported a suggestion as a message the user had typed and left
// unsent ("waiting to send: kick off the 558M cooldown"). It was never typed
// by anyone.
//
// The distinguishing bit survives all the way to /api/sessions/screen, which
// serves the host's parsed grid WITH its SGR intact: the suggestion arrives
// under ESC[2m. hop's own MCP layer already splits real from ghost this way
// (getComposerState in mcp/hop-mcp.js, via isDim()); this is the same rule
// applied to the one surface that was still guessing from flat text.
const PROMPT_GLYPHS = new Set(["❯", ">", "$", "»"]);
export const composerFromScreen = (ansi) => {
  if (!ansi) return null;
  // Only the last few lines can be the composer, and scanning up from the
  // bottom keeps a transcript that happens to quote a prompt out of it.
  const lines = ansi.split("\n").slice(-16);
  for (let i = lines.length - 1; i >= 0; i--) {
    let dim = false, typed = "", suggestion = "", started = false, sawPrompt = false;
    // Walk the line applying SGR as we go: ESC[2m turns dim on, and 0/22 turn
    // it off. Cursor-motion escapes (ESC[<n>C) are column jumps the grid
    // writes for runs of blanks — they separate words, so they become spaces.
    const re = /\x1b\[([0-9;]*)([A-Za-z])/g;
    const raw = lines[i];
    let at = 0, m;
    const emit = (text) => {
      for (const ch of text) {
        if (ch === "\r" || ch === "\n") continue;
        if (!started) {
          // A composer line opens with its prompt glyph or box edge; the text
          // before that is frame, not content.
          if (PROMPT_GLYPHS.has(ch)) { sawPrompt = true; started = true; continue; }
          if (ch === "│") { started = true; continue; }
          if (ch.trim() === "") continue;
          return;                       // ordinary output line — not a composer
        }
        if (ch === "│") continue;       // right-hand box edge
        if (dim) suggestion += ch; else typed += ch;
      }
    };
    while ((m = re.exec(raw)) !== null) {
      emit(raw.slice(at, m.index));
      at = m.index + m[0].length;
      if (m[2] === "m") {
        for (const p of (m[1] || "0").split(";")) {
          if (p === "2") dim = true;
          else if (p === "0" || p === "" || p === "22") dim = false;
        }
      } else if (m[2] === "C" && started) {
        emit(" ");                      // a column jump is whitespace
      }
    }
    emit(raw.slice(at));
    if (!started || (!sawPrompt && !typed.trim() && !suggestion.trim())) continue;
    const clean = (s) => s.replace(/ /g, " ").replace(/\s+/g, " ").trim();
    return { typed: clean(typed), suggestion: clean(suggestion) };
  }
  return null;
};

// Scrubbed: this runs from the SAME cwd (hop2) as the "hop" terminal itself,
// so hop's own cross-directory clobber guard in claude-session-hook.js never
// catches it. If this is ever invoked (deliberately, while debugging, or by
// any future automation) from inside a hop terminal — where HOP_SESSION is
// set — an un-scrubbed env lets this throwaway `claude -p` conversation get
// recorded as THAT terminal's primary one, and the next `hop restore`
// resumes the digest's one-shot chat instead of the user's real history.
// Measured: exactly this clobbered the "hop" session's actual weeks-long
// conversation with a 13-line digest run.
const run = (bin, args, input) =>
  new Promise((resolve, reject) => {
    const env = { ...process.env };
    delete env.HOP_SESSION;
    delete env.CLAUDE_CODE_SESSION_ID;
    const p = execFile(bin, args, { maxBuffer: 32 * 1024 * 1024, timeout: 240000, env },
      (err, stdout) => (err ? reject(err) : resolve(stdout)));
    if (input) { p.stdin.write(input); p.stdin.end(); }
  });

// Change detection state: a hash per session of its last-read screen tail,
// NORMALISED — digits and whitespace runs collapsed — so a claude timer
// ("Sautéed for 2m 15s") or a progress counter ticking in place does not
// count as news. The tradeoff is explicit: a line whose ONLY change is a
// number is treated as a timer, because real results arrive as new lines
// around the number, not as an in-place digit swap.
const STATE_PATH = path.join(os.homedir(), ".hop2/hop-digest-state.json");
const normalise = (t) => t.replace(/[0-9]+/g, "#").replace(/\s+/g, " ");
const tailHash = (t) => crypto.createHash("sha1").update(normalise(t)).digest("hex");
const loadState = () => {
  try { return JSON.parse(fs.readFileSync(STATE_PATH, "utf8")); } catch { return { sessions: {} }; }
};

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
    // The SAME screen with its styling intact, which is the only place the
    // typed/suggested distinction survives. Separate call because the preview
    // is deliberately plain text for everything else that renders it.
    let composer = null;
    try {
      const scr = await api(`/api/sessions/screen?name=${encodeURIComponent(s.internalName)}`);
      composer = composerFromScreen(scr.data || "");
    } catch { /* no composer reading is better than a wrong one */ }
    seen.push({
      session: s.internalName,
      name: s.displayName || s.name,
      about: s.tagline || "",
      wants_you: !!s.attention,
      idle_seconds: s.lastActivityAt
        ? Math.round(Date.now() / 1000 - s.lastActivityAt) : null,
      // Only when there is something to say — an empty box is the normal
      // state and does not need a line in the payload.
      ...(composer && (composer.typed || composer.suggestion)
        ? { input_box: {
              ...(composer.typed ? { typed_by_user: composer.typed } : {}),
              ...(composer.suggestion ? { autocomplete_suggestion: composer.suggestion } : {})
            } }
        : {}),
      screen
    });
  }

  // Only sessions that MEANINGFULLY changed since the last run go to the
  // model in full; the rest ride along as names, for fleet context at no
  // cost. If nothing changed at all, there is no edition — an hourly
  // cadence is only affordable because a quiet hour costs nothing (Jian:
  // "suppress if truly no update").
  const state = loadState();
  const hashes = Object.fromEntries(seen.map((s) => [s.session, tailHash(s.screen)]));
  const changed = seen.filter((s) =>
    hashes[s.session] !== state.sessions?.[s.session] || (s.wants_you && !state.rangBefore?.[s.session]));
  const unchanged = seen.filter((s) => !changed.includes(s)).map((s) => s.name);
  const saveState = () => {
    fs.mkdirSync(path.dirname(STATE_PATH), { recursive: true });
    fs.writeFileSync(STATE_PATH, JSON.stringify({
      sessions: hashes,
      rangBefore: Object.fromEntries(seen.map((s) => [s.session, !!s.wants_you]))
    }, null, 1));
  };
  if (changed.length === 0) {
    saveState();
    console.log("no meaningful update since last edition — suppressed");
    return;
  }
  const prevEdition = (() => {
    for (const out of OUTS) {
      try { return JSON.parse(fs.readFileSync(out, "utf8")); } catch { /* next */ }
    }
    return null;
  })();

  // The paper's own back-issues: past editions, newest first, so the writer
  // KNOWS what the reader has been told across the last days — a thread can
  // be followed to its landing, and a story that has sat unresolved edition
  // after edition can be called a stall, which no single hour's screens can
  // reveal. Generous but bounded: whole editions ride along until the byte
  // budget is spent; the newest is skipped because it rides in full above.
  const HISTORY_BYTE_BUDGET = 24_000;
  const editionHistory = (() => {
    let editions = [];
    for (const out of OUTS) {
      try {
        editions = JSON.parse(fs.readFileSync(
          path.join(path.dirname(out), "digest-archive.json"), "utf8")).editions || [];
        break;
      } catch { /* next root */ }
    }
    const kept = [];
    let bytes = 0;
    for (const e of editions) {
      if (e.generated_at && e.generated_at === prevEdition?.generated_at) continue;
      const slim = {
        generated_at: e.generated_at,
        summary: e.summary,
        items: (e.items || []).map((i) => ({ session: i.session, headline: i.headline, why: i.why }))
      };
      bytes += JSON.stringify(slim).length;
      if (bytes > HISTORY_BYTE_BUDGET) break;
      kept.push(slim);
    }
    return kept;
  })();

  const prompt = `You are the user's co-scientist, not a status board.

They run a lab through these terminals: model training and evaluation,
reproductions, data pipelines, and the software that carries them. Some
sessions are their own work; most are agents working for them. Below is every live
session — what it is for, whether it rang for attention, how long it has been
idle, and the tail of its screen right now.

READING THE INPUT BOX. Do not infer from the screen text whether someone has
typed something and left it unsent — the screen is flat text and cannot show
you the difference. When a session's input box has anything in it, an
\`input_box\` field says exactly what, already disambiguated:
- \`typed_by_user\` is real, human-entered text sitting unsent. That is worth
  reporting: they walked away mid-sentence.
- \`autocomplete_suggestion\` is Claude Code's own greyed-out completion,
  offered but NOT accepted and NOT entered by anyone. It is not pending work,
  not a decision they left open, and not worth a word in the briefing.
No \`input_box\` field means the box is empty. Treating a suggestion as
something the user typed has been the single most common error in these
editions; the field exists so you never have to guess.

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

Write it like the front page of a newspaper. The summary is the headline.
Each item is a short STORY, not a status line: the app prints the session's
name as its dateline, so open with what happened and read as prose under that
dateline. A front page carries a handful of stories chosen well — prefer a few
with substance over coverage of everything; fold related minor updates into a
sentence inside a bigger story when they share a project.

Write for the reader, not the wire. The screens are full of vocabulary the
AGENTS invented — experiment IDs, issue numbers, file and branch names,
internal labels like "exp_0036" or "issue 29" — that the reader never typed
and cannot resolve. Translate every such handle into what it refers to ("the
third RNA ablation that was queued Friday", "the port-cleanup bug it found in
review") or drop it; keep an identifier only when it is one the reader
themselves uses. The "about" line on each session is the reader's OWN words
for what it is for — prefer its vocabulary over anything on the screen.
Numbers that carry meaning (metrics, counts, durations) stay; labels that
carry none go.

The test for every sentence: someone who knows their own projects well but
has not read these terminals should understand it on the FIRST pass. Plain
sentences — what happened, what it means, what to do — beat dense clauses
packed with references. With only a handful of stories there is room to write
them properly; terse is not the goal, clear is.

Two real constraints. The whole page shows at once — no fold, no "more" — so
it must fit one phone screen END TO END: with an item count around four or
five, headline plus why per story is the budget. And each item must name
exactly one session, because each becomes a button they tap to open it.

Reply with ONLY a JSON object:
{"generated_at":"<ISO8601>","summary":"<the one thing to know, in a sentence>",
 "items":[{"session":"<internalName exactly as given>",
           "headline":"<what happened, concretely>",
           "why":"<what it means or puts at risk, one sentence>",
           "urgency":"needs-you"|"blocked"|"finished"|"fyi"}]}

Editions run hourly, and the reader has already seen your previous one —
it is included below, with earlier editions under it (newest first). Do
not re-report what they already told the reader unless something moved; a
story that merely continues can be one clause inside a new story or
absent. The back-issues are your memory, so use them for what one hour's
screens cannot show: follow a thread to its landing ("the sweep promised
Tuesday finished"), and say so plainly when something has sat unresolved
edition after edition — a quiet stall is front-page news precisely
because no single hour makes it visible. Sessions listed under
"unchanged" have not changed meaningfully since the previous edition —
mention one only if a CHANGED session's story needs it.

Previous edition:
${prevEdition ? JSON.stringify({ summary: prevEdition.summary, items: prevEdition.items }, null, 1) : "(none)"}

Earlier editions (newest first):
${editionHistory.length ? JSON.stringify(editionHistory, null, 1) : "(none)"}

Sessions with meaningful updates:
${JSON.stringify(changed, null, 1)}

Unchanged since the previous edition: ${unchanged.join(", ") || "(none)"}`;

  const raw = await run("claude", ["-p", "--model", MODEL], prompt);
  const json = raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1);
  const digest = JSON.parse(json);
  digest.model = MODEL;
  // OUR clock, always: the model fabricates plausible timestamps (measured:
  // an edition stamped noon that ran at 15:42), and the archive and the
  // read-ledgers key on this value.
  digest.generated_at = new Date().toISOString();
  saveState();
  // The agent judged the changes not newsworthy: keep the current edition
  // current rather than pushing an empty page over it.
  if (!(digest.items?.length) && prevEdition) {
    console.log(`agent judged nothing newsworthy — edition kept (${MODEL})`);
    return;
  }
  // The archive: editions accumulate newest-first, capped — the newspaper
  // stack you can leaf back through, not a stream that overwrites itself.
  let archive = [];
  for (const out of OUTS) {
    try { archive = JSON.parse(fs.readFileSync(
      path.join(path.dirname(out), "digest-archive.json"), "utf8")).editions || []; break; }
    catch { /* next root */ }
  }
  archive.unshift(digest);
  // Deep enough that the prompt's byte-budgeted history (above) is fed by
  // days of editions, not hours; still one bounded file the phone can leaf.
  archive = archive.slice(0, 48);
  const body = JSON.stringify(digest, null, 1);
  const archiveBody = JSON.stringify({ editions: archive }, null, 1);
  for (const out of OUTS) {
    fs.writeFileSync(out, body);
    fs.writeFileSync(path.join(path.dirname(out), "digest-archive.json"), archiveBody);
  }
  console.log(`${OUTS.join(", ")}: ${digest.items?.length ?? 0} items (${MODEL}), archive=${archive.length}`);
};

main().catch((e) => { console.error(String(e)); process.exit(1); });
