#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)"

# Build icon if missing
if [[ ! -f Resources/AppIcon.icns ]]; then
  echo "Generating AppIcon.icns…"
  swift scripts/generate-icon.swift Resources/AppIcon.iconset
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
  rm -rf Resources/AppIcon.iconset
fi

swift build -c release

APP="Roobytes.app"
BIN=".build/release/Roobytes"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/Roobytes"
cp Resources/Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$RESOURCES/AppIcon.icns"
# Classic APPL package marker — helps Launch Services / some launchers
printf 'APPL????' > "$CONTENTS/PkgInfo"
chmod +x "$MACOS/Roobytes"

# Ad-hoc sign for local launch
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# /Applications — Raycast + Spotlight / Launch Services
if [[ -w /Applications ]] || mkdir -p /Applications 2>/dev/null; then
  rm -rf /Applications/Roobytes.app
  cp -R "$APP" /Applications/Roobytes.app
  codesign --force --deep --sign - /Applications/Roobytes.app >/dev/null 2>&1 || true
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f /Applications/Roobytes.app
  fi
  mdimport /Applications/Roobytes.app >/dev/null 2>&1 || true
else
  echo "warning: could not write /Applications — install manually: cp -R Roobytes.app /Applications/" >&2
fi

# Drop stale ~/Applications copy from older package scripts
if [[ -d "${HOME}/Applications/Roobytes.app" ]]; then
  rm -rf "${HOME}/Applications/Roobytes.app"
fi

echo "Built Roobytes.app (${VERSION} build ${BUILD})"
echo "  local:  ./Roobytes.app"
echo "  install: /Applications/Roobytes.app"
echo "  open with: open -a Roobytes   or   open ./Roobytes.app"
