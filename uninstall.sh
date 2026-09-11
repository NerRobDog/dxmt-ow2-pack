#!/bin/bash
# Take this pack back out.
#
#   bash uninstall.sh --dry-run   list what would go, and its size. Removes nothing
#   bash uninstall.sh             remove the home, give the bottle's config back
#
# The game is never touched: the files in the bottle belong to whoever installed them,
# and this pack only ever added a block to one config file.
set -eu
. "$(cd "$(dirname "$0")" && pwd -P)/common.sh"

DRY=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown flag %s\n' "$a" >&2; exit 2 ;;
    esac
done

HOME_DIR=$(pack_home)
BOTTLE=$(cat "$HOME_DIR/.bottle" 2>/dev/null || true)
[ -n "$BOTTLE" ] || BOTTLE=$(resolve_bottle "${OW2_BOTTLE:-}" 2>/dev/null || true)
CONF="$BOTTLE/cxbottle.conf"
BAK="$CONF.dxmt-ow2-pack.bak"
PLAIN="$CONF.dxmt-ow2-pack.plain"

have_home=0
[ -d "$HOME_DIR" ] && have_home=1

# Anything of ours in that bottle counts, not just the one key. A bottle left stripped
# by a --plain run that was killed carries none of our keys and an injected
# CX_GRAPHICS_BACKEND instead; judging it untouched would abandon both.
have_conf=0
if [ -n "$BOTTLE" ] && [ -f "$CONF" ]; then
    for key in $OUR_KEYS; do
        if [ -n "$(python3 "$PACK_ROOT/cxenv.py" get "$CONF" "$key" 2>/dev/null || true)" ]; then
            have_conf=1
            break
        fi
    done
    { [ -f "$BAK" ] || [ -f "$PLAIN" ]; } && have_conf=1
fi

if [ "$have_home" = "0" ] && [ "$have_conf" = "0" ]; then
    printf 'nothing to remove: no home at %s, and no settings of ours in the bottle.\n' "$HOME_DIR"
    exit $E_NOTHING
fi

if [ "$have_home" = "1" ]; then
    printf 'home:   %s (%s)\n' "$HOME_DIR" "$(du -sh "$HOME_DIR" 2>/dev/null | awk '{print $1}')"
fi
if [ "$have_conf" = "1" ]; then
    printf 'bottle: %s — our keys removed from cxbottle.conf' "$BOTTLE"
    [ -f "$PLAIN" ] && printf ', a half-finished --plain run undone'
    [ -f "$BAK" ] && printf ', backup file removed'
    printf '\n'
fi

[ "$DRY" = "1" ] && exit 0

if [ "$have_conf" = "1" ] && [ -n "$BOTTLE" ] && bottle_busy "$BOTTLE"; then
    die10 "that bottle is running. Quit the game and Battle.net first."
fi

if [ "$have_conf" = "1" ]; then
    # A killed --plain run first: that file holds the config as it was before the run,
    # and everything below assumes the bottle is in the state this pack left it in.
    if [ -f "$PLAIN" ]; then
        cp "$PLAIN" "$CONF"
        rm -f "$PLAIN"
    fi
    # Remove what we added rather than restoring the whole file. The backup is a
    # snapshot from install time, and anything the person changed in that bottle since
    # — a HUD variable, a different template — is theirs to keep.
    # shellcheck disable=SC2086
    python3 "$PACK_ROOT/cxenv.py" unset "$CONF" $OUR_KEYS
    # CX_GRAPHICS_BACKEND is not ours to keep OR to delete blindly: install removed the
    # person's value, and --plain may have injected one. Put back exactly what the
    # backup says was there, and nothing if it says nothing.
    python3 "$PACK_ROOT/cxenv.py" unset "$CONF" CX_GRAPHICS_BACKEND
    if [ -f "$BAK" ]; then
        prev=$(python3 "$PACK_ROOT/cxenv.py" get "$BAK" CX_GRAPHICS_BACKEND 2>/dev/null || true)
        [ -n "$prev" ] && python3 "$PACK_ROOT/cxenv.py" set "$CONF" "CX_GRAPHICS_BACKEND=$prev"
        rm -f "$BAK"
    fi
fi

if [ "$have_home" = "1" ]; then
    # Never rm -rf a directory on the strength of a variable alone. A home of ours has
    # our marks in it; anything else is someone's data and this script has no business
    # with it.
    if [ -f "$HOME_DIR/BUILD-ID" ] || [ -f "$HOME_DIR/.bottle" ] || [ -d "$HOME_DIR/dxmt" ]; then
        rm -rf "$HOME_DIR"
    else
        die10 "$HOME_DIR does not look like a pack home (no BUILD-ID, no .bottle, no dxmt/).
Refusing to delete it. Remove it yourself if it really is one."
    fi
fi
printf 'done. The game, the bottle and your Battle.net install are untouched.\n'
