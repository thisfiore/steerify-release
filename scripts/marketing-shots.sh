#!/bin/zsh
# Framed marketing pictures from the demo shots: site/assets/shots/marketing/<case>.png (3200×2000) + web/<case>.jpg (1600).
#   scripts/marketing-shots.sh [case…]     (default: every case in frame.html)
# Run after scripts/demo-shots.sh (both DEMOs) and scripts/ios-shots.sh (both DEMOs).
set -e
ROOT=${0:A:h:h}
DIR=$ROOT/site/assets/shots/marketing
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
CASES=($@); (( $#CASES )) || CASES=(hero decide test mark voice roadmap sessions phone)
PROFILE=$(mktemp -d)
mkdir -p $DIR/web
for c in $CASES; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 --window-size=1600,1000 \
    --virtual-time-budget=4000 --user-data-dir=$PROFILE --allow-file-access-from-files \
    --screenshot=$DIR/$c.png "file://$DIR/frame.html?case=$c" 2>/dev/null
  sips -s format jpeg -s formatOptions 82 -Z 1600 $DIR/$c.png --out $DIR/web/$c.jpg >/dev/null
  echo "  $c"
done
rm -rf $PROFILE
echo "→ $DIR"
