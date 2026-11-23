#!/bin/zsh
# Takes old Steerify test copies out of macOS's app list (System Settings › Menu Bar, "Open with"):
# every registered Steerify.app except the one you use, plus the bare "SteerApp" runs' settings.
# Usage: scripts/clean-test-copies.sh [path of your Steerify.app]   (default: /Applications/Steerify.app, else build/Steerify.app)
set -u
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
KEEP=${1:-}
[[ -z $KEEP && -d /Applications/Steerify.app ]] && KEEP=/Applications/Steerify.app
[[ -z $KEEP ]] && KEEP=${0:A:h:h}/build/Steerify.app
KEEP=${KEEP:A}
n=0
$LS -dump 2>/dev/null | sed -nE 's/^path: +(.*\/[^/]*Steer[^/]*\.app) \(0x[0-9a-f]+\)$/\1/p' | sort -u | while read -r p; do
  [[ $p == $KEEP || $p == *iphonesimulator* || $p == */Updater.app ]] && continue
  $LS -u "$p" 2>/dev/null; n=$((n+1)); echo "forgot  $p"
done
# A test run that was never an .app (swift run) shows up as "SteerApp": its settings keep the menu bar row.
[[ -f ~/Library/Preferences/SteerApp.plist ]] && defaults delete SteerApp 2>/dev/null; rm -f ~/Library/Preferences/SteerApp.plist && echo "removed SteerApp settings"
$LS -f "$KEEP" && echo "kept    $KEEP"
