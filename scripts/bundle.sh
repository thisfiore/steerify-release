#!/bin/zsh
# Builds Steerify.app (release) into ./build.
#   scripts/bundle.sh            app only, signed with Developer ID if the cert is in the keychain (else ad-hoc)
#   scripts/bundle.sh --open     same, then open it
#   scripts/bundle.sh --dmg      app + build/Steerify-<version>.dmg (notarized + stapled when signed with Developer ID)
# Version: VERSION file (e.g. 0.5.0). Build number: commits on HEAD.
# Signing: STEERIFY_SIGN_ID overrides the auto-detected "Developer ID Application" identity.
# Notarizing: keychain profile $NOTARY_PROFILE (default "steerify"), made once with
#   xcrun notarytool store-credentials steerify --apple-id <id> --team-id <team> --password <app-specific password>
set -e
cd "$(dirname "$0")/.."
OPEN=0; DMG=0
for a in "$@"; do case $a in --open) OPEN=1;; --dmg) DMG=1;; esac; done

VERSION=$(tr -d ' \n' < VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
SIGN_ID=${STEERIFY_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}
PROFILE=${NOTARY_PROFILE:-steerify}

swift build -c release
APP=build/Steerify.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SteerApp "$APP/Contents/MacOS/Steerify"
if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/skills" && cp -R skills/steerify "$APP/Contents/Resources/skills/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Steerify</string>
  <key>CFBundleDisplayName</key><string>Steerify</string>
  <key>CFBundleIdentifier</key><string>com.frenkfiore.steerify</string>
  <key>CFBundleExecutable</key><string>Steerify</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>com.frenkfiore.steerify</string><key>CFBundleURLSchemes</key><array><string>steerify</string></array></dict></array>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST

if [ -n "$SIGN_ID" ]; then
  # Hardened runtime + secure timestamp: required for notarization.
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --deep "$APP"
  echo "built $APP $VERSION ($BUILD), signed: $SIGN_ID"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1
  echo "built $APP $VERSION ($BUILD), ad-hoc signed (no Developer ID Application cert in the keychain)"
fi

if [ $DMG = 1 ]; then
  OUT=build/Steerify-$VERSION.dmg
  STAGE=build/dmg; rm -rf "$STAGE" "$OUT"; mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "Steerify $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$OUT"
  rm -rf "$STAGE"
  if [ -n "$SIGN_ID" ]; then
    codesign --force --timestamp --sign "$SIGN_ID" "$OUT"
    if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
      xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait
      xcrun stapler staple "$OUT"
      spctl -a -t open --context context:primary-signature -v "$OUT"
      echo "notarized $OUT"
    else
      echo "NOT notarized: no notarytool profile '$PROFILE' (see the top of this script)" >&2
    fi
  else
    echo "NOT notarized: needs a Developer ID Application cert" >&2
  fi
  shasum -a 256 "$OUT"
fi

[ $OPEN = 1 ] && open "$APP"
true
