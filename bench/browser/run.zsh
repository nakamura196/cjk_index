#!/usr/bin/env zsh
# Runs the browser measurement in Google Chrome (headless) and Safari on macOS.
#
# Prerequisite: bench/browser/build.rb has written bench/browser/cache/.
# Usage (from the repository root):
#   zsh bench/browser/run.zsh [runs]          # default 5 runs per size
# Writes bench/browser/results/chrome.json and safari.json.
# Safari opens a window on the desktop; close it when the run is done.
set -euo pipefail

RUNS=${1:-5}
SIZES=(1000 5000 16951)
HERE=${0:A:h}
URL=http://127.0.0.1:8765/page.html
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

wait_for() {  # wait until the server process exits (at most 30 minutes)
  local pid=$1 i=0
  while ps -p $pid >/dev/null && [ $i -lt 360 ]; do sleep 5; i=$((i+1)); done
  if ps -p $pid >/dev/null; then echo "timed out"; kill $pid; return 1; fi
  wait $pid
}

# Chrome: a fresh profile, so nothing is cached between runs of this script.
node $HERE/serve.mjs chrome $RUNS $SIZES & SERVER=$!
sleep 1
PROFILE=$(mktemp -d)
"$CHROME" --headless=new --user-data-dir=$PROFILE --no-first-run --enable-precise-memory-info "$URL?browser=chrome" >/dev/null 2>&1 & BROWSER=$!
wait_for $SERVER
kill $BROWSER 2>/dev/null || true
rm -rf $PROFILE

# Safari: opens a normal window (Safari has no headless mode).
node $HERE/serve.mjs safari $RUNS $SIZES & SERVER=$!
sleep 1
open -a Safari "$URL?browser=safari"
wait_for $SERVER

"$CHROME" --version
defaults read /Applications/Safari.app/Contents/Info CFBundleShortVersionString
