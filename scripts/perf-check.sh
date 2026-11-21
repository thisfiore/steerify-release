#!/bin/zsh
# Performance check: the key areas of the app timed on a copy of this project's real board, against the budgets in
# scripts/perf-budgets.json. Runs before every release (scripts/release.sh) and before delivering a feature.
#   scripts/perf-check.sh             build, then check (exit 1 if a budget is broken)
#   scripts/perf-check.sh --no-build  use build/Steerify.app as it is
# Each result is appended to .steerify/perf.jsonl (date, version, commit, numbers), so every build's speed is kept.
# Runs as test copies (--background, own settings, copied boards): your projects, sessions and settings are untouched.
set -e
cd "$(dirname "$0")/.."
BUILD=1; [ "$1" = "--no-build" ] && BUILD=0
[ $BUILD = 1 ] && scripts/bundle.sh >/dev/null
BIN=build/Steerify.app/Contents/MacOS/Steerify
BUDGETS=$PWD/${STEERIFY_PERF_BUDGETS:-scripts/perf-budgets.json}   # another file only to test the check itself
[ -x $BIN ] || { echo "no $BIN"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf $TMP; defaults delete com.frenkfiore.steerify.perfcheck >/dev/null 2>&1 || true' EXIT
# The real board (what you scroll every day) + the demo project to switch to. Pictures are linked, not copied.
mkdir -p $TMP/steer-app/.steerify $TMP/tiny-todo
rsync -a --exclude img --exclude protos .steerify/ $TMP/steer-app/.steerify/
ln -s $PWD/.steerify/img $TMP/steer-app/.steerify/img
[ -d .steerify/protos ] && ln -s $PWD/.steerify/protos $TMP/steer-app/.steerify/protos
cp -R demo/tiny-todo/.steerify $TMP/tiny-todo/
echo "[\"$TMP/steer-app/.steerify\",\"$TMP/tiny-todo/.steerify\"]" > $TMP/ws.json
export STEERIFY_WORKSPACES=$TMP/ws.json STEERIFY_PREFS_SUITE=com.frenkfiore.steerify.perfcheck

run() {   # run <args…> → prints the result JSON
  local out=$TMP/r.json; rm -f $out
  defaults delete $STEERIFY_PREFS_SUITE >/dev/null 2>&1 || true
  if [[ " $* " == *" --switch-bench "* ]]; then $BIN --background --project steerify "${@[1,-2]}" $out "${@[-1]}" 8 >/dev/null 2>&1 || true
  else $BIN --background --project steerify "$@" $out 8 >/dev/null 2>&1 || true; fi
  cat $out 2>/dev/null || echo '{}'
}

VERSION=$(tr -d ' \n' < VERSION); SHA=$(git rev-parse --short HEAD)
ITEMS=$(node -e "const b=require('./.steerify/board.json');let n=0;for(const t of b.tracks||[])n+=(t.items||[]).length;console.log(n)")
print -P "%F{yellow}▸%f Performance check · Steerify $VERSION ($SHA) · board with $ITEMS key results"
FAIL=0; RESULTS=()
for c in $(node -e "require('$BUDGETS').checks.forEach(c=>console.log(c.id))"); do
  read -r NAME METRIC LIMIT TARGET OTHER ARGS <<< "$(node -e "
    const c=require('$BUDGETS').checks.find(c=>c.id==='$c');
    console.log([c.name.replace(/ /g,'_'),c.metric,c.limit,c.target,c.other||'-',c.args.join(' ')].join(' '))")"
  A=(${=ARGS}); [ "$OTHER" != "-" ] && A+=($OTHER)
  R=$(run $A); V=$(node -e "console.log((JSON.parse(process.argv[1])['$METRIC'])??'')" "$R")
  # One retry over the limit: a single noisy run must not stop a release.
  if [ -z "$V" ] || (( V > LIMIT )); then R=$(run $A); V=$(node -e "console.log((JSON.parse(process.argv[1])['$METRIC'])??'')" "$R"); fi
  if [ -z "$V" ]; then STATE="%F{red}NO RESULT%f"; FAIL=1
  elif (( V > LIMIT )); then STATE="%F{red}SLOWER  (limit $LIMIT ms)%f"; FAIL=1
  elif (( V > TARGET )); then STATE="%F{yellow}ok      (target $TARGET ms)%f"
  else STATE="%F{green}on target%f"; fi
  print -P "  ${(r:22:)${NAME//_/ }} ${(l:7:)V} ms  $STATE"
  RESULTS+=("\"$c\":{\"value\":${V:-null},\"metric\":\"$METRIC\",\"limit\":$LIMIT,\"target\":$TARGET,\"raw\":$R}")
done
echo "{\"at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"version\":\"$VERSION\",\"sha\":\"$SHA\",\"items\":$ITEMS,\"ok\":$([ $FAIL = 0 ] && echo true || echo false),\"checks\":{${(j:,:)RESULTS}}}" >> .steerify/perf.jsonl
if [ $FAIL = 1 ]; then print -P "%F{red}✗%f Performance check failed: an area got slower than its budget ($BUDGETS)."; exit 1; fi
print -P "%F{green}✓%f Performance check passed"
