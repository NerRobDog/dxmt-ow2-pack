#!/bin/bash
# Take this pack back out.
#
#   bash uninstall.sh --dry-run   list what would go, and its size. Removes nothing
#   bash uninstall.sh             remove the home, put the bottle's config back
#
# The game itself is never touched: the files in the bottle belong to whoever
# installed them, and this pack only ever added a block to one config file.
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

have_home=0; [ -d "$HOME_DIR" ] && have_home=1
have_conf=0
if [ -n "$BOTTLE" ] && [ -f "$CONF" ] && \
   [ -n "$(python3 "$PACK_ROOT/cxenv.py" get "$CONF" WINEDLLPATH 2>/dev/null || true)" ]; then
    have_conf=1
fi

if [ "$have_home" = "0" ] && [ "$have_conf" = "0" ]; then
    printf 'nothing to remove: no home at %s, and no settings of ours in the bottle.\n' "$HOME_DIR"
    exit $E_NOTHING
fi

if [ "$have_home" = "1" ]; then
    printf 'home:   %s (%s)\n' "$HOME_DIR" "$(du -sh "$HOME_DIR" 2>/dev/null | awk '{print $1}')"
fi
if [ "$have_conf" = "1" ]; then
    if [ -f "$BAK" ]; then
        printf 'bottle: %s — cxbottle.conf restored from the backup taken at install\n' "$BOTTLE"
    else
        printf 'bottle: %s — our keys removed from cxbottle.conf (no backup found)\n' "$BOTTLE"
    fi
fi

[ "$DRY" = "1" ] && exit 0

if [ "$have_conf" = "1" ] && [ -n "$BOTTLE" ] && bottle_busy "$BOTTLE"; then
    die10 "that bottle is running. Quit the game and Battle.net first."
fi

if [ "$have_conf" = "1" ]; then
    if [ -f "$BAK" ]; then
        cp "$BAK" "$CONF"; rm -f "$BAK"
    else
        # shellcheck disable=SC2086
        python3 "$PACK_ROOT/cxenv.py" unset "$CONF" $OUR_KEYS
    fi
fi
[ "$have_home" = "1" ] && rm -rf "$HOME_DIR"
printf 'done. The game, the bottle and your Battle.net install are untouched.\n'
