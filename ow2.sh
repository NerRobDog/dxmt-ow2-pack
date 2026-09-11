#!/bin/bash
# Start Overwatch in the bottle this pack was installed against.
#
#   ./ow2.sh              play, with this pack's DXMT
#   ./ow2.sh --plain      play on D3DMetal instead, for comparison
#   ./ow2.sh --dry-run    print what would happen, do nothing
#
# setup.sh writes this file into the game home with the paths filled in.
#
# WHY THERE IS A LAUNCHER AT ALL, WHEN THE BOTTLE ALREADY CARRIES THE SETTINGS
#
# A bottle reads its [EnvironmentVariables] when a wine session starts, not when a
# program does. Start the game while a session is already up — Battle.net left
# running, say — and it inherits the previous session's settings, which is how an
# installed pack appears to do nothing at all. This refuses instead of pretending.
#
# WHAT --plain MEANS HERE
#
# CrossOver's launcher assigns every key in [EnvironmentVariables] unconditionally
# (lib/perl/CXBottle.pm), so the bottle's config beats anything exported here. Turning
# DXMT off for one launch therefore means lifting our block out of the config, putting
# CX_GRAPHICS_BACKEND=d3dmetal in, and putting the config back when the session ends —
# not exporting a variable and hoping.
set -eu

HOME_DIR="__HOME__"
PACK_ROOT="__PACK__"
CX="${CX_ROOT:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"

mode=dxmt
dry=0
for a in "$@"; do
    case "$a" in
        --plain)   mode=plain ;;
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown flag %s\n' "$a" >&2; exit 2 ;;
    esac
done

BOTTLE=$(cat "$HOME_DIR/.bottle" 2>/dev/null || true)
[ -n "$BOTTLE" ] && [ -d "$BOTTLE" ] || {
    printf 'no bottle recorded in %s/.bottle — run setup.sh again\n' "$HOME_DIR" >&2
    exit 10
}
CONF="$BOTTLE/cxbottle.conf"
# Overwatch's own shortcut first, Battle.net's as the fallback: launching the game
# starts the client anyway, and starting the client leaves a person one more click
# away from playing.
TARGET="${OW2_TARGET:-}"
if [ -z "$TARGET" ]; then
    for candidate in "$BOTTLE/drive_c/users/Public/Desktop/Overwatch.lnk" \
                     "$BOTTLE/drive_c/users/Public/Desktop/Battle.net.lnk"; do
        [ -e "$candidate" ] && { TARGET="$candidate"; break; }
    done
fi

printf 'backend: %s\n' "$([ "$mode" = plain ] && echo d3dmetal || echo dxmt)"
printf 'bottle:  %s\n' "$BOTTLE"
printf 'target:  %s\n' "${TARGET:-(none found)}"
printf 'command: %s/bin/cxstart --bottle "%s" "%s"\n' "$CX" "$BOTTLE" "${TARGET:-?}"
if [ "$mode" = dxmt ]; then
    printf 'WINEDLLPATH=%s\n' "$(python3 "$PACK_ROOT/cxenv.py" get "$CONF" WINEDLLPATH 2>/dev/null || echo '(not set)')"
fi

[ "$dry" = "1" ] && exit 0

[ -n "$TARGET" ] && [ -e "$TARGET" ] || {
    printf 'no Overwatch or Battle.net shortcut in %s/drive_c/users/Public/Desktop.
Pass the one to start as OW2_TARGET, or start the game once from CrossOver so the
shortcut exists.\n' "$BOTTLE" >&2
    exit 10
}

# The session has to be a fresh one, or the settings above are decoration.
if command -v lsof >/dev/null 2>&1 && \
   lsof +D "$BOTTLE/drive_c" 2>/dev/null | grep -q 'wineserver\|Overwatch'; then
    printf 'that bottle is already running. Quit Battle.net and Overwatch first — the
settings are read when a wine session starts, so a launch into a live session would
silently use the previous ones.\n' >&2
    exit 10
fi

if [ "$mode" = dxmt ]; then
    exec "$CX/bin/cxstart" --bottle "$BOTTLE" "$TARGET"
fi

# --plain: lift our block, run, put it back — including on Ctrl-C.
PLAIN_BAK="$CONF.dxmt-ow2-pack.plain"
cp "$CONF" "$PLAIN_BAK"
restore() {
    [ -f "$PLAIN_BAK" ] || return 0
    cp "$PLAIN_BAK" "$CONF"
    rm -f "$PLAIN_BAK"
    printf 'restored the bottle to this pack'"'"'s DXMT settings.\n'
}
trap restore EXIT INT TERM

# shellcheck disable=SC2086
python3 "$PACK_ROOT/cxenv.py" unset "$CONF" \
    WINEDLLPATH WINEDLLOVERRIDES DXMT_CONFIG_FILE DXMT_USE_DEFAULT_METAL_CACHE \
    DXMT_METALFX_SPATIAL_SWAPCHAIN DXMT_LOG_LEVEL DXMT_LOG_PATH
python3 "$PACK_ROOT/cxenv.py" set "$CONF" "CX_GRAPHICS_BACKEND=d3dmetal"

"$CX/bin/cxstart" --bottle "$BOTTLE" "$TARGET" || true
# cxstart returns as soon as the program is handed off; the session outlives it, and
# putting the config back before the session ends would change what the NEXT launch
# gets rather than this one. Wait for the session.
WINEPREFIX="$BOTTLE" "$CX/bin/wineserver" -w 2>/dev/null || true
