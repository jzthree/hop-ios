#!/usr/bin/env node
// LAN bridge for the HopSpike SPIKE ONLY: exposes the local hay-host WS port
// to the LAN so the iPhone can attach without hop auth changes.
// SECURITY: anyone on your Wi-Fi can reach your terminals while this runs.
// Run it only during spike testing, Ctrl+C after. Usage:
//   node tools/lan-bridge.mjs            # bridges 0.0.0.0:9877 -> hay-host port
import net from "node:net";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const LISTEN = Number(process.argv[2] || 9877);
const state = JSON.parse(fs.readFileSync(path.join(os.homedir(), ".hop2", ".hay-host-state"), "utf8"));
const target = state.port;

const lanIps = Object.values(os.networkInterfaces()).flat()
  .filter((i) => i && i.family === "IPv4" && !i.internal).map((i) => i.address);

const server = net.createServer((client) => {
  const upstream = net.connect(target, "127.0.0.1");
  client.pipe(upstream).pipe(client);
  const drop = () => { client.destroy(); upstream.destroy(); };
  client.on("error", drop); upstream.on("error", drop);
});
server.listen(LISTEN, "0.0.0.0", () => {
  console.log(`bridging 0.0.0.0:${LISTEN} -> 127.0.0.1:${target} (hay-host)`);
  console.log(`iPhone URL:  ws://${lanIps[0] || "<mac-ip>"}:${LISTEN}/ws`);
  console.log(`CAUTION: LAN-exposed while running. Ctrl+C when done.`);
});
