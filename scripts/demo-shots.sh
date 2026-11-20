#!/bin/zsh
# Every key screen of Steerify, on the frozen demo project (Tiny Todo), in one command.
#   scripts/demo-shots.sh            build the app, then shoot
#   scripts/demo-shots.sh --no-build use build/Steerify.app as it is
#   scripts/demo-shots.sh test road  only those shots
# Out: site/assets/shots/demo/<name>.png, window 1500×940 rendered at 2× (3000 px wide). The app is dark-only.
# Runs as a test copy (--background + STEERIFY_WORKSPACES): your projects, sessions and settings are untouched.
set -e
cd "$(dirname "$0")/.."
BUILD=1; ONLY=()
for a in "$@"; do case $a in --no-build) BUILD=0;; *) ONLY+=($a);; esac; done
[ $BUILD = 1 ] && scripts/bundle.sh >/dev/null
BIN=build/Steerify.app/Contents/MacOS/Steerify
OUT=site/assets/shots/demo; mkdir -p $OUT
TMP=$(mktemp -d)
BOARD=$(node scripts/demo-stage.mjs $TMP/tiny-todo 20)
echo "[\"$BOARD\"]" > $TMP/workspaces.json

# name | app arguments (the key screens of the product)
SHOTS=(
  "ready|--tab ready"
  "test|--tab test"
  "test-preview|--tab test --preview test:first-version"
  "choices|--tab choice"
  "choice-making|--tab choice --preview choice:due-dates"
  "requirements|--tab req"
  "roadmap|--tab road"
  "release|--tab release"
  "new-request|--tab test --request Filter: show only what is left"
  "search|--tab road --palette due"
)
for s in $SHOTS; do
  name=${s%%|*}; args=${s#*|}
  (( ${#ONLY} )) && [[ -z ${ONLY[(r)$name]} ]] && continue
  # --request / --palette take the rest of the line as one argument
  if [[ $args == *--request* ]]; then set -- ${=args%%--request*} --request "${args#*--request }"
  elif [[ $args == *--palette* ]]; then set -- ${=args%%--palette*} --palette "${args#*--palette }"
  else set -- ${=args}; fi
  STEERIFY_WORKSPACES=$TMP/workspaces.json $BIN --background --project tiny-todo "$@" --snapshot $PWD/$OUT/$name.png 6 >/dev/null 2>&1 || true
  [ -f $OUT/$name.png ] && echo "$name  $(sips -g pixelWidth $OUT/$name.png | awk '/pixelWidth/{print $2}') px" || echo "$name  FAILED"
done
rm -rf $TMP
