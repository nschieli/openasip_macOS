#!/usr/bin/env bash
#
# test-proxim-quit.sh — launch Proxim and quit it, N times, and count the hangs.
#
# ⛔⛔⛔ THIS HARNESS DOES NOT REPRODUCE THE QUIT DEADLOCK. DO NOT TRUST A GREEN
#      FROM IT AS EVIDENCE THAT THE DEADLOCK IS FIXED.
#
#      Measured 2026-09-20 against the UNFIXED binary, which hangs roughly one
#      time in two under File->Quit: this harness reported 6 clean exits out of
#      6. It is kept because the control was run and is worth preserving, not
#      because the test is.
#
#      Why it misses: an Apple Event quit is delivered to ProximMainFrame as a
#      close event, and onClose runs ProximQuitCmd and then ALWAYS vetoes —
#      AppleScript even reports the veto as "User canceled (-128)". The hang is
#      on the menu item, which is Proxim's own COMMAND_QUIT id dispatched
#      through onCommandEvent. Two different doors into the same teardown, and
#      only one of them was ever observed to jam.
#
#      ⇒ To exercise the real path you must click File->Quit, which needs UI
#        scripting and therefore an Accessibility grant:
#            osascript -e 'tell application "System Events" to tell process
#              "proxim" to click menu item "Quit" of menu "File" of menu bar 1'
#        Until that is wired up and ITSELF controlled against the unfixed
#        binary, the fix is verified BY HAND or not at all.
#
# ⚠ THE CONTROL IS THE POINT. A harness that cannot fail on the broken build
#   cannot pass on the fixed one; it just prints a colour. Run any replacement
#   against a known-bad binary FIRST.
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
# ⛔⛔ THE BINARY UNDER TEST IS WRAPPED IN A THROWAWAY BUNDLE WITH A UNIQUE
#     BUNDLE ID, AND ADDRESSED BY THAT ID. `tell application "Proxim" to quit`
#     resolves through LaunchServices by NAME, which on a machine that has the
#     product installed finds the INSTALLED Proxim — a different, older binary
#     living somewhere else entirely. The test would then launch, quit and
#     report on the build it was not testing, and pass. Verified on this box:
#     `path to application "Proxim"` answered with the installed copy.
# ⚠ A quit event needs a bundle to be addressable at all, so the wrapper is
#   also what makes this testable without Accessibility permissions.
# ⚠ DO NOT USE `path to application` TO CHECK ANY OF THIS: it LAUNCHES the
#   application it resolves. Looking up "Proxim" that way started the installed
#   copy on a developer's desktop.
#
# Usage: test-proxim-quit.sh <prefix> [iterations] [seconds-to-wait]
#   e.g. test-proxim-quit.sh ./local 20
set -uo pipefail

PREFIX="${1:?usage: test-proxim-quit.sh <prefix> [iterations] [timeout]}"
N="${2:-10}"
LIMIT="${3:-15}"
PROXIM="$PREFIX/bin/proxim"

[ -x "$PROXIM" ] || { echo "⛔ no proxim at $PROXIM"; exit 1; }
PROXIM=$(cd "$(dirname "$PROXIM")" && pwd)/proxim     # absolute, for the wrapper

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUNDLE_ID="org.openasip.proxim-quit-test"
WRAP=$(mktemp -d)/ProximQuitTest.app
APP_EXE="$WRAP/Contents/MacOS/ProximQuitTest"

cleanup() {
    [ -d "$WRAP" ] && "$LSREGISTER" -u "$WRAP" >/dev/null 2>&1
    rm -rf "$(dirname "$WRAP")"
}
trap cleanup EXIT

mkdir -p "$WRAP/Contents/MacOS"
cat > "$WRAP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>       <string>ProximQuitTest</string>
    <key>CFBundleExecutable</key> <string>ProximQuitTest</string>
    <key>CFBundleIdentifier</key> <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key>    <string>1</string>
</dict>
</plist>
PLIST
# ⚠ dyld resolves @loader_path from the symlink's TARGET, so the prefix's own
#   lib/ is still what gets loaded — the wrapper does not re-home anything.
ln -s "$PROXIM" "$APP_EXE"
"$LSREGISTER" -f "$WRAP" >/dev/null 2>&1

echo "── binary under test : $PROXIM"
echo "── wrapper bundle    : $WRAP  ($BUNDLE_ID)"

hangs=0; clean=0; failed_launch=0; undeliverable=0
echo "── $N iterations of: launch $PROXIM, quit it, wait up to ${LIMIT}s"
echo

for i in $(seq 1 "$N"); do
    # ⚠ `open -n` RATHER THAN RUNNING THE BINARY. LaunchServices then owns the
    #   process and knows which bundle it is, which is what makes the quit
    #   event deliverable. Running the executable directly leaves that to
    #   inference.
    # ⛔ AND IT EXECS THE RESOLVED PATH, NOT THE BUNDLE PATH. The process shows
    #    up as $PROXIM, never as .../MacOS/ProximQuitTest, so searching for the
    #    wrapper name finds nothing and every iteration reports "did not start"
    #    while Proxim visibly opens and closes. Found by NS running it.
    before=$(pgrep -f "$PROXIM" | tr '\n' ' ')
    open -n "$WRAP" >/dev/null 2>&1

    # Give it time to reach the idle state: the worker thread must actually be
    # inside readLine()'s wait, which is where the lost signal used to land.
    pid=""; waited=0
    while [ "$waited" -lt 20 ] && [ -z "$pid" ]; do
        for c in $(pgrep -f "$PROXIM"); do
            case " $before " in *" $c "*) : ;; *) pid="$c"; break ;; esac
        done
        [ -z "$pid" ] && { sleep 0.5; waited=$((waited+1)); }
    done
    if [ -z "$pid" ]; then
        printf '%3d  ⛔ did not start\n' "$i"; failed_launch=$((failed_launch+1)); continue
    fi
    sleep 3

    # ⚠ THE APPLE EVENT, NOT A SIGNAL. SIGTERM would kill the process without
    #   ever running Proxim::OnExit(), so it would pass on the broken build
    #   too and prove nothing. A quit event goes through the same teardown a
    #   menu Quit does, which is the path that deadlocked.
    # ⛔ BY BUNDLE ID, NOT BY NAME — see the header. By name this addresses
    #    whichever Proxim LaunchServices likes best, which is not this one.
    # ⛔⛔ ERROR -128 IS A DELIVERED EVENT, NOT A FAILED ONE. Proxim's
    #     ProximMainFrame::onClose ALWAYS calls event.Veto() — it runs
    #     ProximQuitCmd (which pushes "quit" to the worker) and then vetoes the
    #     close, because the real teardown happens later on
    #     EVT_SIMULATOR_TERMINATED. AppleScript reports that veto as
    #     "User canceled (-128)" and a non-zero exit. Treating that as
    #     undeliverable threw away every single measurement.
    qout=$(osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>&1); qrc=$?
    if [ "$qrc" -ne 0 ] && ! printf '%s' "$qout" | grep -q -- '-128'; then
        # ⛔ A QUIT WE COULD NOT DELIVER IS NOT A HANG, AND MUST NOT BE COUNTED
        #    AS ONE. Reporting a delivery failure as a passing or failing quit
        #    would make this whole harness meaningless in exactly the way the
        #    bug it tests for is meaningless — silently measuring nothing.
        printf '%3d  ⛔ could not deliver the quit event: %s\n' "$i" "$qout"
        undeliverable=$((undeliverable+1))
        kill -9 "$pid" 2>/dev/null
        continue
    fi

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
    fi
done

echo
echo "clean exits        : $clean / $N"
echo "hangs              : $hangs"
[ "$failed_launch" -gt 0 ]  && echo "failed to start    : $failed_launch"
[ "$undeliverable" -gt 0 ]  && echo "quit undeliverable : $undeliverable"
[ "$hangs" -gt 0 ] && echo "stacks written to /tmp/proxim-hang-*.txt"
echo
# ⛔ GREEN REQUIRES EVERY ITERATION TO HAVE ACTUALLY BEEN TESTED. clean == N is
#    the only pass; anything undelivered or unstarted means the harness did not
#    measure what it claims to, which is not a pass and not a fix.
if [ "$hangs" -eq 0 ] && [ "$clean" -eq "$N" ]; then echo "✅ GREEN — $N quits, no hangs"; exit 0; fi
if [ "$hangs" -eq 0 ]; then
    echo "⛔ INCONCLUSIVE — no hangs, but only $clean of $N iterations were actually tested"
    exit 2
fi
echo "⛔ RED — $hangs hang(s) in $N"; exit 1
