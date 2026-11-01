#!/bin/zsh
# Release build → /Applications/BootVolume.app
#
# Signing identity, in order:
#   1. $BOOTVOLUME_SIGN_ID (e.g. "Apple Development: you@example.com (ABCDE12345)")
#   2. the first "Apple Development" identity in your keychain
#   3. ad-hoc ("-")
# The app checks its own signature before installing the root helper, so any of these works.
set -e
cd "${0:a:h}"
APP=/Applications/BootVolume.app

IDENTITY="${BOOTVOLUME_SIGN_ID:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"')" || true
fi
[[ -z "$IDENTITY" ]] && IDENTITY="-"

swift build -c release
pkill -x BootVolume 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp .build/release/BootVolume "$APP/Contents/MacOS/BootVolume"
cp Resources/* "$APP/Contents/Resources/"
# --options runtime: hardened runtime
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "==> $APP (signed: $IDENTITY)"
