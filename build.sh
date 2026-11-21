#!/bin/bash
# Build "MEEMO Print.app" and MEEMO-Print.dmg into build/. Needs Xcode command line tools and, to bundle the
# two vendor driver files, an installed QY Printer driver (they are copied from the system, never stored in git).
#   ./build.sh                                   unsigned (ad-hoc) build
#   SIGN_ID="Developer ID Application: ..." NOTARY_PROFILE=name ./build.sh    signed + notarized
#   (create the profile once with: xcrun notarytool store-credentials name)
set -euo pipefail
cd "$(dirname "$0")"
VERSION=1.2.0
APP="build/MEEMO Print.app"; RES="$APP/Contents/Resources"
rm -rf build; mkdir build

osacompile -o "$APP" src/droplet.applescript
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos12" -o "build/helper-$arch" src/helper.swift
done
lipo -create build/helper-arm64 build/helper-x86_64 -output "$RES/helper"; rm build/helper-*
cp src/print_pdf.sh src/bg_print.sh "$RES/"; chmod +x "$RES"/*.sh
# Vendor files go in untouched, keeping the vendor's own signature.
mkdir "$RES/driver"
cp /usr/libexec/cups/filter/rastertoM08F /Library/Printers/PPDs/Contents/Resources/M832.ppd "$RES/driver/"

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

DMG=build/MEEMO-Print.dmg
mkdir build/dmg; ditto "$APP" "build/dmg/MEEMO Print.app"; ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname "MEEMO Print" -srcfolder build/dmg -ov -format UDZO "$DMG"; rm -rf build/dmg
if [ "$ID" != - ]; then codesign --timestamp -s "$ID" "$DMG"; fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
echo "built build/MEEMO-Print.dmg ($ID)"
