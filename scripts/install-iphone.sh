#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${MY_STOCK_DEVICE:?Set the paired iPhone device identifier}"
: "${MY_STOCK_TEAM:?Set the Apple development team identifier}"
export MY_STOCK_API_URL="${MY_STOCK_API_URL:-https://my-stock-blue.vercel.app}"
export MY_STOCK_READER_TOKEN_FILE="${MY_STOCK_READER_TOKEN_FILE:-.local/reader-token}"
export MY_STOCK_DEVICE
mkdir -p .local
# A personal development installation provisions the read key at first launch.
# The token is never added to a build setting, bundle, or command argument.
xcodebuild -project MyStock.xcodeproj -scheme MyStock -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build-device \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$MY_STOCK_TEAM" \
  MY_STOCK_API_URL="$MY_STOCK_API_URL" build > .local/iphone-build.log 2>&1
xcrun devicectl device install app --device "$MY_STOCK_DEVICE" \
  'build-device/Build/Products/Debug-iphoneos/My Stock.app'
python3 - <<'PY'
import os, pathlib, subprocess
env = dict(os.environ)
env['DEVICECTL_CHILD_MY_STOCK_SERVER'] = os.environ['MY_STOCK_API_URL']
env['DEVICECTL_CHILD_MY_STOCK_KEY'] = pathlib.Path(os.environ['MY_STOCK_READER_TOKEN_FILE']).read_text().strip()
subprocess.run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device',
               os.environ['MY_STOCK_DEVICE'], '--terminate-existing', 'com.charlie.mystock'],
               env=env, check=True)
PY
