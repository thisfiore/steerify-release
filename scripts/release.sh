#!/bin/zsh
# One release, the same every time: this is steer-app's "deploy" in steerify.json, so the Release tab's
# Deploy button and Claude's /steerify ship both run it.
#   scripts/release.sh             release
#   scripts/release.sh --dry-run   everything local (version, DMG, notes, public copy), nothing pushed or published
# Steps: checks → version (bumps the patch if this one is already released) → push private main (site deploys)
#        → DMG (notarized when the Developer ID cert + notary profile exist) → notes from approved items
#        → public repo sync → GitHub Release with the DMG on the public repo → tag v<version> in both repos.
set -e
cd "$(dirname "$0")/.."
PUBLIC_SLUG=${STEERIFY_PUBLIC_SLUG:-thisfiore/steerify-release}
DRY=0; [ "$1" = "--dry-run" ] && DRY=1
say() { print -P "%F{yellow}▸%f $*"; }
die() { print -P "%F{red}✗%f $*" >&2; exit 1; }

# 1. Checks: the DMG must be exactly a pushed commit of main.
command -v gh >/dev/null || die "gh not installed (brew install gh)"
gh auth status >/dev/null 2>&1 || die "gh not logged in (gh auth login)"
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || die "not on main"
DIRTY=$(git status --porcelain --untracked-files=no -- . ':!.steerify')
if [ -n "$DIRTY" ]; then [ $DRY = 1 ] && say "(dry run) would stop: uncommitted changes outside .steerify" || die "uncommitted changes outside .steerify — commit or stash them first:\n$DIRTY"; fi
git pull -q --rebase --autostash origin main

# 2. Version: VERSION, bumped once if that release already exists.
VERSION=$(tr -d ' \n' < VERSION)
if gh release view "v$VERSION" -R $PUBLIC_SLUG >/dev/null 2>&1; then
  VERSION=$(echo $VERSION | awk -F. '{print $1"."$2"."$3+1}')
  echo $VERSION > VERSION
  [ $DRY = 1 ] && say "would bump to $VERSION" || { git add VERSION; git commit -q -m "Release $VERSION"; }
fi
say "Steerify $VERSION"
PREV=$(gh release list -R $PUBLIC_SLUG --limit 1 --json publishedAt -q '.[0].publishedAt' 2>/dev/null)
SINCE=${PREV:-2026-11-18}   # first release: everything approved since the v0.5 notes

# 3. Private main pushed first (steerify.dev deploys from it).
[ $DRY = 1 ] && say "would push private main" || git push -q origin main
SHA=$(git rev-parse --short HEAD)

# 4. DMG.
[ $DRY = 1 ] && [ -n "$(git status --porcelain VERSION)" ] && trap 'git checkout -q VERSION' EXIT
scripts/bundle.sh --dmg
DMG=build/Steerify-$VERSION.dmg
[ -f $DMG ] || die "no $DMG"
if xcrun stapler validate -q $DMG >/dev/null 2>&1; then PRE=(); say "notarized"
else PRE=(--prerelease); say "not notarized → pre-release (testers: Privacy & Security → Open Anyway)"; fi

# 5. Notes from the board.
NOTES=build/release-notes-$VERSION.md
node scripts/release-notes.mjs $VERSION $SINCE > $NOTES
if [ ${#PRE} -gt 0 ]; then
  printf '\n> Not notarized yet: after the first try to open it, go to System Settings → Privacy & Security → Open Anyway.\n' >> $NOTES
fi
say "notes: $NOTES"; sed 's/^/    /' $NOTES

# 6. Public repo + GitHub Release.
if [ $DRY = 1 ]; then
  scripts/publish-public.sh
  say "dry run done: would publish v$VERSION ($SHA) with $(du -h $DMG | cut -f1) DMG on $PUBLIC_SLUG"
  exit 0
fi
scripts/publish-public.sh --push
gh release create "v$VERSION" $DMG -R $PUBLIC_SLUG --target main --title "Steerify $VERSION" --notes-file $NOTES $PRE
git tag -f "v$VERSION" && git push -q -f origin "v$VERSION"
say "released: https://github.com/$PUBLIC_SLUG/releases/tag/v$VERSION"
