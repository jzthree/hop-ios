#!/usr/bin/env node
// probe.mjs — drive a hop session from outside the iOS app, for verification.
//
// This is the tool behind most of the evidence in STATUS.md: real bells, size
// elections, known fixtures. Every action SENDS REAL INPUT to a real session —
// use scratch sessions (create/delete via the daemon API) unless you mean it.
//
//   node tools/probe.mjs <room> ring              ring BEL once ("answer me")
//   node tools/probe.mjs <room> fill N            seq 1 N + END-MARKER line
//   node tools/probe.mjs <room> type "text\n"     raw input, \n = Enter
//   node tools/probe.mjs <room> clear N           N delete keystrokes
//   node tools/probe.mjs <room> hold C R SECS     win the size election at CxR
//                                                 and HOLD it by typing every
//                                                 1.5s (space+DEL, prompt-safe)
//
// Why hold types: the election follows typing recency, and a phone attaching
// sends an attach claim that beats anyone idle >2.5s — a silent probe loses
// the size the moment the app opens the session.
//
// Scratch sessions:
//   TOKEN=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.hop2/.tunnel-state')))['sessionSecret'])")
//   curl -s -X POST https://$HOP_HOST/api/sessions -H "Authorization: Bearer $TOKEN" \
//        -H 'Content-Type: application/json' -d '{"name":"scratch","type":"terminal"}'
//   ... and delete with /api/sessions/delete {"internalName":"scratch"}
import WebSocket from '/Users/jianzhou/Code/hop2/hay/node_modules/ws/index.js';
import fs from 'fs';

const [room, action, ...rest] = process.argv.slice(2);
if (!room || !action) { console.log('usage: probe.mjs <room> <action> [args]'); process.exit(1); }
const secret = JSON.parse(fs.readFileSync(process.env.HOME + '/.hop2/.tunnel-state')).sessionSecret;
// The server can move (a per-user subdomain once the bare domain becomes a
// public landing page), so don't bake a hostname in. HOP_HOST overrides;
// otherwise ask the local daemon where it says home is.
const hopHost = process.env.HOP_HOST || (() => {
  try {
    const cfg = JSON.parse(fs.readFileSync(process.env.HOME + '/.hop2/.config.json'));
    if (cfg.canonicalHost) return cfg.canonicalHost;
  } catch (e) { /* fall through */ }
  try {
    return JSON.parse(fs.readFileSync(process.env.HOME + '/.hop2/.domain-config.json')).hostname;
  } catch (e) { return null; }
})();
if (!hopHost) { console.error('No hop host: set HOP_HOST=<hostname>'); process.exit(1); }
const sleep = ms => new Promise(r => setTimeout(r, ms));

const cols = action === 'hold' ? Number(rest[0]) : 80;
const rows = action === 'hold' ? Number(rest[1]) : 24;
const ws = new WebSocket(`wss://${hopHost}/ws?room=${room}&name=probe&source=probe&cols=${cols}&rows=${rows}&replay=1&token=${secret}`);
const send = data => ws.send(JSON.stringify({ type: 'input', data }));

ws.on('open', async () => {
  await sleep(600);
  switch (action) {
    case 'ring':
      send("printf 'answer me " + String.fromCharCode(7) + "'\n");
      await sleep(1200); console.log('rang'); break;
    case 'fill': {
      const n = Number(rest[0] || 30);
      send(`seq 1 ${n}; echo END-MARKER\n`);
      await sleep(1200); console.log(`filled ${n}`); break;
    }
    case 'type':
      send(rest.join(' ').replace(/\\n/g, '\n'));
      await sleep(800); console.log('typed'); break;
    case 'clear': {
      const n = Number(rest[0] || 1);
      send(String.fromCharCode(127).repeat(n));
      await sleep(600); console.log(`cleared ${n}`); break;
    }
    case 'hold': {
      const secs = Number(rest[2] || 60);
      // Witness: a deliberate (user:true) claim from another client takes the
      // size DESPITE this hold's typing recency — log the loss so tests can
      // assert on it.
      ws.on('message', raw => {
        try {
          const m = JSON.parse(raw);
          if (m.type === 'active_size' && (m.cols !== cols || m.rows !== rows))
            console.log(`lost size to ${m.cols}x${m.rows}`);
        } catch {}
      });
      send(' ' + String.fromCharCode(127));          // become the recent typist
      await sleep(400);
      ws.send(JSON.stringify({ type: 'resize', cols, rows }));
      console.log(`holding ${cols}x${rows} for ${secs}s`);
      for (let i = 0; i < Math.ceil(secs / 1.5); i++) {
        send(' ' + String.fromCharCode(127));
        await sleep(1500);
      }
      break;
    }
    default:
      console.log('unknown action', action); process.exit(1);
  }
  ws.close(); process.exit(0);
});
ws.on('error', e => { console.log('err', e.message); process.exit(1); });
