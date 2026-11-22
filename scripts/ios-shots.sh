#!/bin/zsh
# iPhone shots of Steerify on a demo board, in the simulator (clean 9:41 status bar).
#   DEMO=tiny-todo scripts/ios-shots.sh      → site/assets/shots/demo/iphone/*.png
#   DEMO=nonna-says scripts/ios-shots.sh     → site/assets/shots/demo-nonna/iphone/*.png
# The board is staged with demo-stage.mjs and opened with -demoBoard (the simulator reads it from the Mac's disk).
set -e
ROOT=${0:A:h:h}
DEMO=${DEMO:-tiny-todo}
SKIP_BUILD=${SKIP_BUILD:-}
APP=com.frenkfiore.steerify.ios
if [ $DEMO = tiny-todo ]; then OUT=$ROOT/site/assets/shots/demo/iphone; TEST=first-version; CHOICE=due-dates
  ASK="Late todos should shout a bit more. Red, maybe a little shake"
else OUT=$ROOT/site/assets/shots/demo-nonna/iphone; TEST=recipe-page; CHOICE=hero-size
  ASK="Cream detector on pasted recipes: show a big red banner when the recipe says cream"; fi
STAGE=$(mktemp -d)/stage
BOARD=$(node $ROOT/scripts/demo-stage.mjs $STAGE 20 $DEMO)

cd $ROOT/ios
if [ -z "$SKIP_BUILD" ]; then
  command -v xcodegen >/dev/null && xcodegen generate -q
  xcodebuild -project Steerify.xcodeproj -scheme Steerify -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES build -quiet
fi
DEV=$(xcrun simctl list devices available | grep -m1 -E "iPhone 18 Pro \(|iPhone 17 Pro \(" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $DEV 2>/dev/null || true
xcrun simctl bootstatus $DEV -b >/dev/null
xcrun simctl status_bar $DEV override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
xcrun simctl uninstall $DEV $APP 2>/dev/null || true     # no leftovers (outbox, link) from earlier runs
xcrun simctl install $DEV build/Build/Products/Debug-iphonesimulator/Steerify.app
mkdir -p $OUT

shot() { local name=$1; shift
  xcrun simctl terminate $DEV $APP 2>/dev/null || true
  xcrun simctl launch $DEV $APP -demoBoard $BOARD -demoLink "$@" >/dev/null
  sleep 5; xcrun simctl io $DEV screenshot $OUT/$name.png 2>/dev/null; echo "  $name"; }

shot ready
shot test -focusTest $TEST
shot choice -focusChoice $CHOICE
shot roadmap -tab road
shot request -request -requestText "$ASK"
[ $DEMO = tiny-todo ] && shot sessions -demoSessions
echo "→ $OUT"
