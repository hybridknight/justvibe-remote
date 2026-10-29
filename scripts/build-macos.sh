#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
OUTPUT="$ROOT/dist/JustVibe Remote.app"
CACHE="$ROOT/build/module-cache"
mkdir -p "$ROOT/dist" "$CACHE"
# Build and sign outside the installed bundle. Failed compilation/signing must
# leave the last working app intact.
STAGING="$(mktemp -d "$ROOT/build/macos-stage.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/JustVibe Remote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/plugins"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 \
  -module-cache-path "$CACHE" "$ROOT"/macos/Sources/*.swift \
  -o "$APP/Contents/MacOS/JustVibeRemote"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/branding/JustVibeRemote.icns" "$ROOT/assets/branding/JustVibeRemote.png" "$APP/Contents/Resources/"
cp -R "$ROOT/plugins/bundled/." "$APP/Contents/Resources/plugins/"
mkdir -p "$APP/Contents/Resources/PluginAuthoring/guides"
cp -R "$ROOT/plugins/examples/device" "$APP/Contents/Resources/PluginAuthoring/device"
for GUIDE in PLUGIN-AUTHORING.md PLUGINS.md IMAGE-TO-PLUGIN.md; do
  cp "$ROOT/docs/$GUIDE" "$APP/Contents/Resources/PluginAuthoring/guides/$GUIDE"
done
if [[ -n "${JUSTVIBEREMOTE_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --sign "$JUSTVIBEREMOTE_SIGNING_IDENTITY" --timestamp=none "$APP"
else
  python3 "$ROOT/scripts/local-signing.py" sign "$APP"
fi
codesign --verify --strict "$APP"
python3 - "$APP" "$OUTPUT" "$STAGING/previous.app" <<'PY'
import os, pathlib, shutil, sys
source, destination, backup = map(pathlib.Path, sys.argv[1:])
had_previous = destination.exists()
if had_previous: os.rename(destination, backup)
try:
    os.rename(source, destination)
except BaseException:
    if had_previous: os.rename(backup, destination)
    raise
if backup.exists(): shutil.rmtree(backup)
PY
print "Built and verified: $OUTPUT"
