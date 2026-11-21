#!/bin/bash
# Build "MEEMO Print.app" and MEEMO-Print.zip into build/. Needs Xcode command line tools.
#   ./build.sh                                   unsigned (ad-hoc) build
#   SIGN_ID="Developer ID Application: ..." NOTARY_PROFILE=name ./build.sh    signed + notarized
#   (create the profile once with: xcrun notarytool store-credentials name)
set -euo pipefail
cd "$(dirname "$0")"
VERSION=1.0.0
APP="build/MEEMO Print.app"; RES="$APP/Contents/Resources"
rm -rf build; mkdir build

osacompile -o "$APP" src/droplet.applescript
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos12" -o "build/helper-$arch" src/helper.swift
done
lipo -create build/helper-arm64 build/helper-x86_64 -output "$RES/helper"; rm build/helper-*
cp src/print_pdf.sh src/bg_print.sh "$RES/"; chmod +x "$RES"/*.sh

P="$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string io.github.rocher71.meemo-print "$P"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$P"
plutil -replace LSMinimumSystemVersion -string 12.0 "$P"
plutil -replace NSBluetoothAlwaysUsageDescription -string "MEEMO Print uses Bluetooth to send pages to your printer." "$P"

cat > build/ent.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.device.bluetooth</key><true/></dict></plist>
EOF
ID="${SIGN_ID:--}"; TS=--timestamp; [ "$ID" = - ] && TS=--timestamp=none
codesign --force --options runtime $TS --entitlements build/ent.plist -s "$ID" "$RES/helper"
codesign --force --options runtime $TS --entitlements build/ent.plist -s "$ID" "$APP"
rm build/ent.plist

zipit() { rm -f build/MEEMO-Print.zip; ditto -c -k --keepParent "$APP" build/MEEMO-Print.zip; }
zipit
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit build/MEEMO-Print.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"; zipit
fi
echo "built build/MEEMO-Print.zip ($ID)"
