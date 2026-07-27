#!/bin/zsh
# upkeep.sh — the whole maintenance tick in one command.
# Usage: tools/upkeep.sh ["48 hours ago"]   (drift window, default 24h)
set -uo pipefail
cd "$(dirname "$0")/.."
export PATH=/Applications/Xcode.app/Contents/Developer/usr/bin:$PATH
WINDOW="${1:-24 hours ago}"

echo "=== upstream drift (hop2 server-side since $WINDOW) ==="
DRIFT=$(cd ~/Code/hop2 && git log --oneline --since="$WINDOW" -- hay/apps/server/src/ hop)
[ -n "$DRIFT" ] && echo "$DRIFT" || echo "none — protocol surface unmoved"

echo "=== unit ===" && make test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
echo "=== ui ===" && make uitest 2>&1 | grep -E "Executed [0-9]+ tests|' failed" | tail -2
echo "=== strict concurrency ===" && make strict 2>&1 | head -1
echo "=== tsan ===" && make tsan 2>&1 | grep -E "races|Executed" | head -2

echo "=== device ==="
xcrun devicectl device info apps --device FA720813-48B6-5E57-984D-C76733368A9D \
  --json-output /tmp/upkeep-apps.json >/dev/null 2>&1 && \
python3 -c "
import json
for a in json.load(open('/tmp/upkeep-apps.json')).get('result',{}).get('apps',[]):
    if 'zhoulab' in str(a.get('bundleIdentifier','')):
        print('installed build:', a.get('bundleVersion'))" || echo "device unreachable"
echo "=== repo build ===" && git rev-list --count HEAD
