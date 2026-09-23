#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
device="${MY_STOCK_SIMULATOR:-$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for r in d["devices"].values() for x in r if x["name"]=="iPhone 17 Pro"))')}"
xcrun simctl boot "$device" 2>/dev/null || true
xcodebuild -project MyStock.xcodeproj -scheme MyStock \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath build \
  CODE_SIGN_IDENTITY=- build > .local/build.log 2>&1
if ! lsof -iTCP:8787 -sTCP:LISTEN -t >/dev/null; then
  nohup node gateway/server.mjs > .local/reader.log 2>&1 &
fi
xcrun simctl install "$device" 'build/Build/Products/Debug-iphonesimulator/My Stock.app'
xcrun simctl terminate "$device" com.charlie.mystock 2>/dev/null || true
MY_STOCK_LAUNCH_DEVICE="$device" python3 - <<'PY'
import os, pathlib, subprocess, time
key = pathlib.Path('.local/reader-token')
for _ in range(50):
    if key.exists(): break
    time.sleep(0.1)
env = dict(os.environ)
env['SIMCTL_CHILD_MY_STOCK_SERVER'] = 'http://127.0.0.1:8787'
env['SIMCTL_CHILD_MY_STOCK_KEY'] = key.read_text().strip()
subprocess.run(['xcrun', 'simctl', 'launch', os.environ['MY_STOCK_LAUNCH_DEVICE'], 'com.charlie.mystock'], env=env, check=True)
PY
if ! lsof -iTCP:3200 -sTCP:LISTEN -t >/dev/null; then
  launchctl remove com.charlie.mystock.serve-sim 2>/dev/null || true
  launchctl submit -l com.charlie.mystock.serve-sim \
    -o "$PWD/.local/serve-sim.log" -e "$PWD/.local/serve-sim.err" \
    -- "$(command -v python3)" -B "$PWD/scripts/serve-sim.py" --device "$device"
fi
if [ -d /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app ]; then
  open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app
fi
echo "My Stock is running on simulator $device."
echo "Codex viewer: http://localhost:3200/"
