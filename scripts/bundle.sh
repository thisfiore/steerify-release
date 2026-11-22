#!/bin/zsh
# Builds Steerify.app (release) into ./build.
#   scripts/bundle.sh            app only, ad-hoc signed: test builds never touch the keychain (no codesign prompt)
#   scripts/bundle.sh --open     same, then open it
#   scripts/bundle.sh --sign     app signed with Developer ID (if the cert is in the keychain)
#   scripts/bundle.sh --dmg      Developer ID app + build/Steerify-<version>.dmg (notarized + stapled)
# Developer ID asks for the key's password on every codesign unless the key lets codesign in:
#   scripts/keychain-allow-codesign.sh   (once, with your login password)
# Version: VERSION file (e.g. 0.5.0). Build number: commits on HEAD.
# Signing: STEERIFY_SIGN_ID overrides the auto-detected "Developer ID Application" identity.
# Notarizing: keychain profile $NOTARY_PROFILE (default "steerify"), made once with
#   xcrun notarytool store-credentials steerify --apple-id <id> --team-id <team> --password <app-specific password>
set -e
cd "$(dirname "$0")/.."
OPEN=0; DMG=0; SIGN=0
for a in "$@"; do case $a in --open) OPEN=1;; --dmg) DMG=1; SIGN=1;; --sign) SIGN=1;; esac; done
[ -n "$STEERIFY_SIGN_ID" ] && SIGN=1

VERSION=$(tr -d ' \n' < VERSION)
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
SIGN_ID=""
[ $SIGN = 1 ] && SIGN_ID=${STEERIFY_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)}
PROFILE=${NOTARY_PROFILE:-steerify}
# Updates: the appcast is an asset of the public repo's latest release (written by release.sh).
# The private half of this key is in the login keychain (generate_keys --account steerify); back it up.
FEED_URL=${STEERIFY_FEED_URL:-https://github.com/thisfiore/steerify-release/releases/latest/download/appcast.xml}
SPARKLE_PUBLIC_KEY=EU+btwrNxFG3oDaH2s+owVBTN4GXeMtwyDEoodK+3YU=

swift build -c release
APP=${STEERIFY_APP_OUT:-build/Steerify.app}   # STEERIFY_APP_OUT=build/test/Steerify.app: a test build that never replaces the app you run
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SteerApp "$APP/Contents/MacOS/Steerify"
# Sparkle (in-app updates): the framework goes in Contents/Frameworks, found through this rpath.
mkdir -p "$APP/Contents/Frameworks"
# Apple Silicon only: Sparkle ships universal, so keep just its arm64 slice (an Intel slice makes macOS 26
# warn "Support Ending for Intel-Based Apps").
ditto --arch arm64 .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Steerify" 2>/dev/null || true
if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/skills" && cp -R skills/steerify "$APP/Contents/Resources/skills/"
# The pixel font for labels (Silkscreen, SIL OFL 1.1: the licence travels with it).
mkdir -p "$APP/Contents/Resources/fonts" && cp fonts/Silkscreen-*.ttf fonts/Silkscreen-OFL.txt "$APP/Contents/Resources/fonts/"
# The demo project (Tiny Todo, frozen by scripts/demo-freeze.mjs): "Try the demo project" copies it out.
[ -d demo/tiny-todo ] && mkdir -p "$APP/Contents/Resources/demo" && cp -R demo/tiny-todo "$APP/Contents/Resources/demo/"
# What's new (the version badge's panel): this version's notes, when release.sh wrote them before bundling.
[ -f build/release-notes-$VERSION.md ] && cp build/release-notes-$VERSION.md "$APP/Contents/Resources/whats-new.md"
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
  <key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Folder</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>public.folder</string></array></dict></array>
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUAutomaticallyUpdate</key><true/>
  <key>SUScheduledCheckInterval</key><integer>14400</integer>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST

# Guard: no Intel code anywhere in the bundle (macOS 26 flags any x86_64 slice).
INTEL=$(find "$APP" -type f -perm +111 -exec sh -c 'lipo -archs "$1" 2>/dev/null | grep -q x86_64 && echo "$1"' _ {} \;)
[ -n "$INTEL" ] && { echo "Intel code in the bundle:\n$INTEL" >&2; exit 1; }

if [ -n "$SIGN_ID" ]; then
  # Hardened runtime + secure timestamp: required for notarization. Sparkle's parts first, inside out.
  SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for part in "$SPK/XPCServices/Installer.xpc" "$SPK/XPCServices/Downloader.xpc" "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$SIGN_ID" "$part"
  done
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
  codesign --verify --strict --deep "$APP"
  echo "built $APP $VERSION ($BUILD), signed: $SIGN_ID"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1
  # Ad-hoc identity = the binary's hash by default, so macOS 26 sees every rebuild as a new app (Menu Bar ›
  # Allow in the Menu Bar keeps the old one, the wheel stays hidden). Tie it to the bundle id instead.
  codesign --force --sign - -r="designated => identifier \"$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")\"" "$APP" >/dev/null 2>&1
  echo "built $APP $VERSION ($BUILD), ad-hoc signed$([ $SIGN = 1 ] && echo ' (no Developer ID Application cert in the keychain)' || echo ' (test build; --sign or --dmg for Developer ID)')"
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
