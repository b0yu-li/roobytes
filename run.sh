#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

./package-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
echo "Starting Roobytes ${VERSION}…"
open -a Roobytes 2>/dev/null || open "./Roobytes.app"
