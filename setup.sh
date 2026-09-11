#!/bin/bash
# dxmt-ow2-pack — install this pack's DXMT into a game home, and point a CrossOver
# bottle at it.
#
#   bash setup.sh --preflight     can this be installed here? writes nothing
#   bash setup.sh                 install (idempotent: run it again to update)
#
# Environment (satoru sets these; by hand they have defaults):
#   SATORU_GAME_HOME   where to install          (default: ~/ow2-pack)
#   SATORU_LOGS        where logs go             (default: <home>/logs)
#   OW2_BOTTLE         bottle name or full path  (default: "Battle.net Desktop App")
#   CX_ROOT            CrossOver's SharedSupport directory
#
# WHAT THIS TOUCHES OUTSIDE THE HOME
#
# One file: the bottle's cxbottle.conf, and only its [EnvironmentVariables] block.
# The previous version is kept as cxbottle.conf.dxmt-ow2-pack.bak. Nothing is ever
# written inside /Applications/CrossOver.app — dropping DLLs into the application
# bundle breaks its signature and the next CrossOver update silently reverts it.
#
# The DLLs live in the home, not in the bottle. That is not tidiness: one of our
# bottles sits on an exFAT volume, which has no extended attributes and no execute
# bits, and the home is on APFS where they behave.
set -eu
. "$(cd "$(dirname "$0")" && pwd -P)/common.sh"

PREFLIGHT=0
for a in "$@"; do
    case "$a" in
        --preflight) PREFLIGHT=1 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown flag %s\n' "$a" >&2; exit 2 ;;
    esac
done

HOME_DIR=$(pack_home)
# DXMT logs into the home, always. The manifest says [paths] logs = "logs", which
# satoru resolves inside SATORU_GAME_HOME, so pointing the layer at SATORU_LOGS
# instead would leave the launcher's "Open logs" looking at a directory that does
# not exist. One place, and it is the one the manifest names.
LOGS="$HOME_DIR/logs"

# ---- checks. Every one of these is a read -------------------------------------
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] \
    || die10 "this pack is for Apple Silicon; this machine is not."

os_major=$(sw_vers -productVersion | cut -d. -f1)
[ "$os_major" -ge 26 ] 2>/dev/null \
    || die10 "macOS 26 or newer is required; this is $(sw_vers -productVersion)."

CX=$(cx_root) || die10 "CrossOver was not found. Install it, or set CX_ROOT to its
SharedSupport/CrossOver directory. This pack runs the game in your own CrossOver
bottle; it does not ship an engine of its own yet."

verify_payload "$PACK_ROOT"
STAMP=$(build_id "$PACK_ROOT")
[ -n "$STAMP" ] || die12 "d3d11.dll carries no version stamp — this is not a release
build of DXMT. The stamp is generated at configure time; whoever built it needs to
run 'meson setup --reconfigure' first."

BOTTLE=$(resolve_bottle "${OW2_BOTTLE:-}") || die10 "no such bottle: ${OW2_BOTTLE:-Battle.net Desktop App}
Looked in ${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}.
Pass OW2_BOTTLE with the bottle's name, or with its full path if it lives on another
volume."
CONF="$BOTTLE/cxbottle.conf"
[ -r "$CONF" ] || die10 "$CONF is not readable — is $BOTTLE a CrossOver bottle?"

if bottle_busy "$BOTTLE"; then
    die10 "that bottle is running right now. Quit the game and Battle.net first — this
pack will not kill anyone's session."
fi

# Already done? The contract says say so with 11 rather than doing it again.
if [ -f "$HOME_DIR/BUILD-ID" ] && [ "$(cat "$HOME_DIR/BUILD-ID" 2>/dev/null)" = "$STAMP" ] \
   && [ "$(python3 "$PACK_ROOT/cxenv.py" get "$CONF" WINEDLLPATH 2>/dev/null)" = "$HOME_DIR/dxmt" ]; then
    printf 'DXMT %s is already installed in %s and the bottle points at it.\n' "$STAMP" "$HOME_DIR"
    exit $E_NOTHING
fi

if [ "$PREFLIGHT" = "1" ]; then
    printf 'ready: DXMT %s -> %s, bottle %s\n' "$STAMP" "$HOME_DIR" "$BOTTLE"
    exit 0
fi

# ---- from here on it writes ---------------------------------------------------
mkdir -p "$HOME_DIR" "$LOGS"
rm -rf "$HOME_DIR/dxmt"
cp -R "$PACK_ROOT/dxmt" "$HOME_DIR/dxmt"
cp "$PACK_ROOT/dxmt.conf" "$HOME_DIR/dxmt.conf"
printf '%s\n' "$BOTTLE" > "$HOME_DIR/.bottle"

# A tarball downloaded in a browser carries the quarantine flag. The DLLs are loaded
# by wine rather than executed by macOS, but the flag travels and costs nothing to
# drop — and satoru has already done it when it is the one driving.
xattr -dr com.apple.quarantine "$HOME_DIR/dxmt" 2>/dev/null || true

# The launcher lives in the home and must keep working when the unpacked pack is
# gone: the contract calls the cache erasable, and satoru replaces it wholesale on
# every install. So the home gets its own copy of everything the launcher calls.
cp "$PACK_ROOT/cxenv.py" "$PACK_ROOT/common.sh" "$HOME_DIR/"
# sed replacement text is not literal: & means "the whole match" and a path may
# contain one. Escape it, and the delimiter, before substituting.
esc_home=$(printf '%s' "$HOME_DIR" | sed -e 's/[&|\\]/\\&/g')
sed -e "s|__HOME__|$esc_home|g" "$PACK_ROOT/ow2.sh" > "$HOME_DIR/ow2.sh"
chmod +x "$HOME_DIR/ow2.sh"

[ -f "$CONF.dxmt-ow2-pack.bak" ] || cp "$CONF" "$CONF.dxmt-ow2-pack.bak"

# WINEDLLPATH names the directory that CONTAINS x86_64-windows/ and x86_64-unix/, not
# the windows one. Pointing it one level too deep is why this pack's bottle-side path
# was never confirmed to work: wine was looking for x86_64-windows/x86_64-windows.
#
# CX_GRAPHICS_BACKEND is removed rather than set: with it, CrossOver injects overrides
# pointing at its own bundled DXMT, which is precisely the copy we are not using.
python3 "$PACK_ROOT/cxenv.py" set "$CONF" \
    "WINEDLLPATH=$HOME_DIR/dxmt" \
    "WINEDLLOVERRIDES=dxgi,d3d11,d3d10core=n,b" \
    "DXMT_CONFIG_FILE=$HOME_DIR/dxmt.conf" \
    "DXMT_USE_DEFAULT_METAL_CACHE=1" \
    "DXMT_METALFX_SPATIAL_SWAPCHAIN=1" \
    "DXMT_LOG_LEVEL=error" \
    "DXMT_LOG_PATH=$LOGS"
python3 "$PACK_ROOT/cxenv.py" unset "$CONF" CX_GRAPHICS_BACKEND

cat > "$HOME_DIR/README-local.txt" <<LOCAL
dxmt-ow2-pack, installed $STAMP

  Home:    $HOME_DIR
  Bottle:  $BOTTLE
  Config:  $HOME_DIR/dxmt.conf     (edit, then restart the game)
  Logs:    $LOGS

Play:            $HOME_DIR/ow2.sh
Without DXMT:    $HOME_DIR/ow2.sh --plain      (D3DMetal, for comparison)
What it will do: $HOME_DIR/ow2.sh --dry-run

In the game's video settings keep Graphics API on DX11. DXMT has no D3D12 path, and
on DX12 none of this applies.

Check it is really this pack's DXMT that got loaded, with the game running:
  $HOME_DIR/ow2.sh --verify
LOCAL

# Last, and only now: the marker that says this home is finished. preflight answers
# 11 on the strength of it, so writing it earlier would let an install interrupted
# halfway be mistaken for a complete one.
printf '%s\n' "$STAMP" > "$HOME_DIR/BUILD-ID"

printf '\nInstalled DXMT %s\n  home:   %s\n  bottle: %s (cxbottle.conf backed up)\n' \
    "$STAMP" "$HOME_DIR" "$BOTTLE"
printf '  play:   %s/ow2.sh\n\nKeep Graphics API on DX11 in the game.\n' "$HOME_DIR"
