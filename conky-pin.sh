#!/bin/bash
# Pin conky to a named RANDR output (default DP-2) and re-launch it
# whenever GNOME/Mutter reports a monitor configuration change.
#
# Why: conky's `xinerama_head` is an index, not a monitor identity, so
# cable swaps silently move conky to the wrong screen. We look up the
# index for the desired output by name on every (re)launch.
#
# Install:  cp conky-pin.sh ~/.local/bin/ && chmod +x ~/.local/bin/conky-pin.sh
# Autostart: edit ~/.config/autostart/conky.desktop:
#            Exec=/home/administrator/.local/bin/conky-pin.sh

set -u

TARGET_OUTPUT="${CONKY_TARGET_OUTPUT:-DP-2}"
STARTUP_DELAY="${CONKY_STARTUP_DELAY:-60}"
SETTLE_RECHECK_DELAY="${CONKY_SETTLE_RECHECK_DELAY:-30}"

find_head_index() {
    xrandr --listmonitors 2>/dev/null | awk -v t="$TARGET_OUTPUT" '
        $NF == t { gsub(":", "", $1); print $1; exit }
    '
}

restart_conky() {
    local idx
    idx=$(find_head_index)
    if [ -z "$idx" ]; then
        echo "conky-pin: output '$TARGET_OUTPUT' not found in xrandr; defaulting to head 0" >&2
        idx=0
    fi
    pkill -x conky 2>/dev/null || true
    sleep 0.3
    CONKY_HEAD="$idx" conky -d
}

sleep "$STARTUP_DELAY"
restart_conky

# Belt-and-suspenders: Mutter sometimes settles the layout after our
# initial query without firing a final MonitorsChanged on the bus, leaving
# conky pinned to a stale head. Re-pin once after the layout has had time
# to settle.
(
    sleep "$SETTLE_RECHECK_DELAY"
    restart_conky
) &

while true; do
    gdbus monitor --session \
        --dest org.gnome.Mutter.DisplayConfig \
        --object-path /org/gnome/Mutter/DisplayConfig 2>/dev/null \
    | while read -r line; do
        case "$line" in
            *MonitorsChanged*)
                sleep 1
                restart_conky
                ;;
        esac
    done
    sleep 5
done
