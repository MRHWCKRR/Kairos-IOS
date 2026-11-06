#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUTPUT="${TOOLBAR_ARTIFACTS:-/tmp/kairos-toolbar-artifacts}"
BUILD="$(mktemp -d /tmp/kairos-toolbar.XXXXXX)"
APP="$BUILD/ToolbarFixture.app"
mkdir -p "$APP" "$OUTPUT"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
xcrun --sdk iphonesimulator swiftc -parse-as-library -target "$ARCH-apple-ios18.0-simulator" -sdk "$SDK" \
  Kairos/Kairos/Theme/KairosIcon.swift Tools/fixtures/ToolbarFixture.swift -o "$APP/ToolbarFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.kairos.toolbar-fixture</string>
<key>CFBundleExecutable</key><string>ToolbarFixture</string>
<key>CFBundleName</key><string>ToolbarFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>18.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict/>
</dict>
</dict></plist>
PLIST
# Use an iOS 26 runtime so the native Liquid Glass toolbar is exercised.
xcrun simctl list -j devices available > "$BUILD/devices.json"
DEVICE="$(python3 - "$BUILD/devices.json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))['devices']
candidates = [d for runtime, ds in devices.items() if 'iOS-26' in runtime for d in ds if d['name'].startswith('iPhone')]
if not candidates: raise SystemExit('An iOS 26 iPhone simulator is required')
print(sorted(candidates, key=lambda d: d['name'])[0]['udid'])
PY
)"
xcrun simctl boot "$DEVICE" || true
xcrun simctl bootstatus "$DEVICE" -b
mkdir -p "$BUILD/Assets.xcassets"
printf '%s\n' '{"info":{"author":"xcode","version":1}}' > "$BUILD/Assets.xcassets/Contents.json"
for ICON in sidebar_simple tray note_pencil dots_three list_bullets funnel plus; do
  cp -R "Kairos/Kairos/Assets.xcassets/kairos_$ICON.imageset" "$BUILD/Assets.xcassets/"
done
xcrun actool "$BUILD/Assets.xcassets" --compile "$APP" --platform iphonesimulator \
  --minimum-deployment-target 18.0 --target-device iphone --output-partial-info-plist "$BUILD/assets.plist"
codesign --force --sign - "$APP"
xcrun simctl install "$DEVICE" "$APP"
for SCREEN in chats backlog; do
  for STATE in enabled disabled accessibility; do
    xcrun simctl terminate "$DEVICE" app.kairos.toolbar-fixture >/dev/null 2>&1 || true
    DATA="$(xcrun simctl get_app_container "$DEVICE" app.kairos.toolbar-fixture data)"
    rm -f "$DATA/Documents/leading.json" "$DATA/Documents/trailing.json"
    ARGS=(--fixture)
    if [ "$SCREEN" = backlog ]; then ARGS+=(--backlog); fi
    if [ "$STATE" = disabled ]; then ARGS+=(--disabled); fi
    if [ "$STATE" = accessibility ]; then ARGS+=(--accessibility); fi
    xcrun simctl launch "$DEVICE" app.kairos.toolbar-fixture "${ARGS[@]}"
    for ATTEMPT in $(seq 1 30); do
      if [ -f "$DATA/Documents/leading.json" ] && [ -f "$DATA/Documents/trailing.json" ]; then break; fi
      sleep 1
    done
    PREFIX="$OUTPUT/$SCREEN-$STATE"
    xcrun simctl io "$DEVICE" screenshot "$PREFIX.png"
    cp "$DATA/Documents/leading.json" "$PREFIX-leading.json"
    cp "$DATA/Documents/trailing.json" "$PREFIX-trailing.json"
    python3 - "$PREFIX" <<'PY'
import json, sys
prefix = sys.argv[1]
reports = [json.load(open(f'{prefix}-{name}.json')) for name in ('leading', 'trailing')]
for r in reports:
    for key in ('labelWidth', 'labelHeight', 'nativeWidth'):
        assert 44 <= r[key] <= 56, f'{prefix} {r["name"]} {key}: {r[key]}pt; {r}'
    # The iOS 26 native visual item is 36pt tall inside a 44pt SwiftUI hit area.
    assert 32 <= r['nativeHeight'] <= 56, f'{prefix} {r["name"]} native height: {r}'
    assert r['y'] < 130, f'Control is not in navigation bar: {r}'
    assert r['titleVisible'], f'Navigation title is missing or hidden: {r}'
assert reports[0]['nativeX'] + reports[0]['nativeWidth'] < reports[1]['nativeX'], 'Toolbar buttons overlap'
assert reports[0]['nativeX'] + reports[0]['nativeWidth'] <= reports[0]['titleX'], 'Leading button overlaps title'
assert reports[1]['titleX'] + reports[1]['titleWidth'] <= reports[1]['nativeX'], 'Trailing button overlaps title'
print(f'PASS {prefix}: rendered leading/trailing native buttons are 44–56pt')
PY
  done
done
