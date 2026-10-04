// After `make testflight` uploads: wait for App Store Connect to finish
// processing this build number, then add it to the Internal tester group
// (hasAccessToAllBuilds is false, so a build reaches no phone until added).
//   node tools/testflight-publish.mjs <buildNumber>
import crypto from 'crypto'; import fs from 'fs'; import os from 'os';
const KEY_ID = process.env.ASC_KEY_ID || 'CCFL4WD4V4';
const ISSUER = process.env.ISSUER || '254072af-7f14-4065-acd8-d09fe4924553';
const APP = '6796157151', GROUP = '407c6174-9f97-4cb8-894c-331562f7755d';
const version = process.argv[2];
if (!version) { console.error('usage: testflight-publish.mjs <buildNumber>'); process.exit(2); }
const key = fs.readFileSync(`${os.homedir()}/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8`, 'utf8');
const jwt = () => {
  const b = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const h = b({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' }), p = b({ iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  return `${h}.${p}.${crypto.sign('sha256', Buffer.from(`${h}.${p}`), { key, dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
};
const api = async (path, method = 'GET', body) => {
  const r = await fetch('https://api.appstoreconnect.apple.com' + path, { method, headers: { Authorization: 'Bearer ' + jwt(), 'Content-Type': 'application/json' }, body: body && JSON.stringify(body) });
  return { status: r.status, json: r.status === 204 ? null : await r.json().catch(() => null) };
};
let build;
for (let i = 0; i < 60; i++) {
  const r = await api(`/v1/builds?filter[app]=${APP}&filter[version]=${version}&fields[builds]=version,processingState`);
  build = r.json?.data?.[0];
  const st = build?.attributes?.processingState;
  console.log(`${new Date().toTimeString().slice(0, 8)} build ${version}: ${st || 'not listed yet'}`);
  if (st === 'VALID') break;
  if (st === 'FAILED' || st === 'INVALID') { console.error('processing failed — check App Store Connect email'); process.exit(1); }
  await new Promise((r) => setTimeout(r, 30_000));
}
if (build?.attributes?.processingState !== 'VALID') { console.error('timed out waiting for processing'); process.exit(1); }
const add = await api(`/v1/betaGroups/${GROUP}/relationships/builds`, 'POST', { data: [{ type: 'builds', id: build.id }] });
if (add.status !== 204) { console.error('add to Internal group failed', add.status, JSON.stringify(add.json)); process.exit(1); }
const d = await api(`/v1/builds/${build.id}/buildBetaDetail?fields[buildBetaDetails]=internalBuildState`);
console.log(`build ${version} → Internal group: ${d.json?.data?.attributes?.internalBuildState}`);
