#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
bin_dir=$(swift build -c release --show-bin-path)
app_bundle="pray.daily.app"
rm -rf "$app_bundle"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp "$bin_dir/pray.daily" "$app_bundle/Contents/MacOS/"
cp Resources/Info.plist "$app_bundle/Contents/"
cp Resources/AppIcon.icns "$app_bundle/Contents/Resources/"
cp -R "$bin_dir/pray.daily_PrayDaily.bundle" "$app_bundle/Contents/Resources/"
for sound in Glass Ping Pop Azan; do
  cp "Resources/Sounds/${sound}.aiff" "$app_bundle/Contents/Resources/"
done
codesign --force --deep --sign - "$app_bundle"
