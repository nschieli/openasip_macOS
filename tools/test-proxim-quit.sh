#!/usr/bin/env bash
#
# test-proxim-quit.sh — launch Proxim and quit it, N times, and count the hangs.
#
# ⛔⛔ THE BUG THIS EXISTS FOR IS INTERMITTENT, WHICH IS WHY "I TRIED IT AND IT
#     WORKED" IS NOT EVIDENCE. Measured on macOS 26.6.2 before the fix: two
#     hangs and two clean exits in four attempts by hand. A fix confirmed by
#     two more attempts would be confirmed by a coin.
#
# The defect: ProximLineReader::readLine() waited on a wxCondition with no
# timeout and no predicate loop, and ProximLineReader::input() signalled that
# condition without holding the mutex. A signal raised outside the wait is
# lost forever, so the worker thread stayed in pthread_cond_wait, never
# reached TestDestroy(), and Proxim::OnExit()'s join never returned. The
# window stayed on screen, the main thread kept pumping events, and macOS drew
# the spinner. Only SIGINT ended it.
#
# ⚠ WHAT COUNTS AS A PASS: the process is gone within the timeout. A run that
#   has to be killed is a hang, whatever it printed.
#
# Usage: test-proxim-quit.sh <prefix> [iterations] [seconds-to-wait]
#   e.g. test-proxim-quit.sh ./local 20
set -uo pipefail

PREFIX="${1:?usage: test-proxim-quit.sh <prefix> [iterations] [timeout]}"
N="${2:-10}"
LIMIT="${3:-15}"
PROXIM="$PREFIX/bin/proxim"

[ -x "$PROXIM" ] || { echo "⛔ no proxim at $PROXIM"; exit 1; }

hangs=0; clean=0; failed_launch=0
echo "── $N iterations of: launch $PROXIM, quit it, wait up to ${LIMIT}s"
echo

for i in $(seq 1 "$N"); do
    "$PROXIM" >/tmp/proxim-quit-test.$i.log 2>&1 &
    pid=$!

    # Give it time to reach the idle state: the worker thread must actually be
    # inside readLine()'s wait, which is where the lost signal used to land.
    waited=0
    while [ "$waited" -lt 10 ] && ! pgrep -x proxim >/dev/null 2>&1; do
        sleep 0.5; waited=$((waited+1))
    done
    if ! kill -0 "$pid" 2>/dev/null; then
        printf '%3d  ⛔ did not start\n' "$i"; failed_launch=$((failed_launch+1)); continue
    fi
    sleep 3

    # ⚠ THE APPLE EVENT, NOT A SIGNAL. SIGTERM would kill the process without
    #   ever running Proxim::OnExit(), so it would pass on the broken build
    #   too and prove nothing. A quit event goes through the same teardown a
    #   menu Quit does, which is the path that deadlocked.
    osascript -e 'tell application "Proxim" to quit' >/dev/null 2>&1 \
        || kill -INT "$pid" 2>/dev/null

    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$LIMIT" ]; do
        sleep 1; waited=$((waited+1))
    done

    if kill -0 "$pid" 2>/dev/null; then
        printf '%3d  HANG  still alive after %ss — sampling, then killing\n' "$i" "$LIMIT"
        sample "$pid" 3 -f "/tmp/proxim-hang-$i.txt" >/dev/null 2>&1
        kill -9 "$pid" 2>/dev/null
        hangs=$((hangs+1))
    else
        printf '%3d  ok    exited after %ss\n' "$i" "$waited"
        clean=$((clean+1))
        rm -f "/tmp/proxim-quit-test.$i.log"
    fi
    wait "$pid" 2>/dev/null
done

echo
echo "clean exits : $clean / $N"
echo "hangs       : $hangs"
[ "$failed_launch" -gt 0 ] && echo "failed to start: $failed_launch"
[ "$hangs" -gt 0 ] && echo "stacks written to /tmp/proxim-hang-*.txt"
echo
[ "$hangs" -eq 0 ] && [ "$clean" -eq "$N" ] && { echo "✅ GREEN"; exit 0; }
echo "⛔ RED"; exit 1
