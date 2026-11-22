#!/bin/zsh
# Every key screen of Steerify, on the frozen demo project (Tiny Todo), in one command.
#   scripts/demo-shots.sh            build the app, then shoot
#   scripts/demo-shots.sh --no-build use build/Steerify.app as it is
#   scripts/demo-shots.sh test road  only those shots
#   DEMO=nonna-says scripts/demo-shots.sh   the second demo (recipes) → site/assets/shots/demo-nonna/
# Out: site/assets/shots/demo/<name>.png, window 1500×940 rendered at 2× (3000 px wide). The app is dark-only.
# Runs as a test copy (--background + STEERIFY_WORKSPACES): your projects, sessions and settings are untouched.
set -e
cd "$(dirname "$0")/.."
BUILD=1; ONLY=()
for a in "$@"; do case $a in --no-build) BUILD=0;; *) ONLY+=($a);; esac; done
[ $BUILD = 1 ] && scripts/bundle.sh >/dev/null
BIN=build/Steerify.app/Contents/MacOS/Steerify
DEMO=${DEMO:-tiny-todo}
OUT=site/assets/shots/demo; [ $DEMO != tiny-todo ] && OUT=site/assets/shots/demo-${DEMO%%-*}
mkdir -p $OUT
TMP=$(mktemp -d)
BOARD=$(node scripts/demo-stage.mjs $TMP/$DEMO 20 $DEMO)
echo "[\"$BOARD\"]" > $TMP/workspaces.json
# The request sheet's "recent screenshots" strip reads this folder, never your Desktop: fill it with demo pictures.
mkdir -p $TMP/shots && i=0
for f in demo/$DEMO/.steerify/img/*/*.png; do i=$((i+1)); cp $f "$TMP/shots/Screenshot 2026-11-20 at 10.4$i.00.png"; done
export STEERIFY_SHOTS_DIR=$TMP/shots
# Sessions show their terminal: a git repo and a throwaway home keep your paths out of the picture.
git -C ${BOARD:h} init -q && git -C ${BOARD:h} -c user.name=demo -c user.email=demo@example.com commit -qam demo --allow-empty >/dev/null 2>&1
mkdir -p $TMP/home

# name | app arguments (the key screens of the product)
if [ $DEMO = tiny-todo ]; then
SHOTS=(
  "ready|--tab ready --since-hours 0"
  "test|--tab test"
  "test-preview|--tab test --preview test:first-version"
  "choices|--tab choice"
  "choice-making|--tab choice --preview choice:due-dates"
  "requirements|--tab req"
  "roadmap|--tab road"
  "release|--tab release"
  "new-request|--tab test --request Filter: show only what is left"
  "search|--tab road --palette due"
  "tasks|--tab task"
  "sessions|--tab ready --flow-demo test:first-version,choice:due-dates,road:filter-all-active-done;working,waiting,idle"
  "request-mark|--tab test --request-img $PWD/demo/tiny-todo/.steerify/img/ship/first-version-week.png --request-mark dot:0.48,0.65;rect:0.31,0.32,0.6,0.09 --request Nonna needs her own list. And Late should shout a bit more"
)
else
SHOTS=(
  "ready|--tab ready --since-hours 0"
  "test|--tab test"
  "test-preview|--tab test --preview test:recipe-page"
  "test-phone|--tab test --preview test:shopping-list"
  "choices|--tab choice"
  "choice-making|--tab choice --preview choice:hero-size"
  "requirements|--tab req"
  "roadmap|--tab road"
  "tasks|--tab task"
  "sessions|--tab ready --flow-demo test:recipe-page,choice:hero-size,road:shopping-list-from-a-recipe;working,waiting,idle"
  "request-mark|--tab test --request-img $PWD/demo/nonna-says/.steerify/img/ship/recipe-page.png --request-mark dot:0.47,0.36;rect:0.23,0.86,0.33,0.12 --request The fork looks like chopsticks. And cream should be bigger: nonna wants it red"
)
fi
for s in $SHOTS; do
  name=${s%%|*}; args=${s#*|}
  (( ${#ONLY} )) && [[ -z ${ONLY[(r)$name]} ]] && continue
  # --request / --palette take the rest of the line as one argument
  if [[ $args == *"--request "* ]]; then set -- ${=args%%--request\ *} --request "${args#*--request }"
  elif [[ $args == *--palette* ]]; then set -- ${=args%%--palette*} --palette "${args#*--palette }"
  else set -- ${=args}; fi
  H=$HOME; [[ $name == sessions ]] && H=$TMP/home
  HOME=$H STEERIFY_WORKSPACES=$TMP/workspaces.json $BIN --background --project $DEMO "$@" --snapshot $PWD/$OUT/$name.png 6 >/dev/null 2>&1 || true
  # The session's terminal shows real paths and the launch command: cover it (empty terminal, nothing to read).
  [[ $name == sessions && -f $OUT/$name.png ]] && swift scripts/blur-region.swift $OUT/$name.png 0.553 0.08 0.874 0.994
  [ -f $OUT/$name.png ] && echo "$name  $(sips -g pixelWidth $OUT/$name.png | awk '/pixelWidth/{print $2}') px" || echo "$name  FAILED"
done
rm -rf $TMP

# Web copies for the landing and the README: 1600 px JPEGs in $OUT/web (the PNGs stay as the full-size originals).
mkdir -p $OUT/web
for f in $OUT/*.png; do sips -s format jpeg -s formatOptions 82 -Z 1600 $f --out $OUT/web/${f:t:r}.jpg >/dev/null; done
