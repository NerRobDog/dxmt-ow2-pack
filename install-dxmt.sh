#!/bin/sh
#
# dxmt-ow2-pack — install a DXMT build into a CrossOver bottle, and only into the bottle.
#
#   ./install-dxmt.sh --dlls <dir> [--bottle "<name>"]   install and wire up the bottle
#   ./install-dxmt.sh --verify                           check a RUNNING game loaded them
#   ./install-dxmt.sh --revert [--bottle "<name>"]       restore the last cxbottle.conf backup
#
# <dir> is a DXMT build directory holding x86_64-windows/{d3d11,dxgi,d3d10core}.dll and
# x86_64-unix/winemetal.so. Build it from https://github.com/NerRobDog/dxmt (branch main),
# or take one from that fork's releases.
#
# WHAT THIS SCRIPT WILL NOT DO
#
# It never writes inside /Applications/CrossOver.app. Dropping DLLs into the application
# bundle is what this project used to do by hand, and it is a bad thing to ask of anyone
# else: it breaks the code signature and the next CrossOver update silently reverts it.
# Everything here lands inside the bottle, which is yours.
#
# HONEST STATUS
#
# The bottle-side override path (WINEDLLPATH + WINEDLLOVERRIDES in cxbottle.conf, with
# CX_GRAPHICS_BACKEND left unset so CrossOver does not inject its own bundled DXMT) has NOT
# yet been confirmed end-to-end on a running match. Run --verify on your first launch: it
# reads the game's loaded modules and tells you which DXMT actually got in. If it reports
# CrossOver's bundled copy, say so in an issue rather than editing the bundle.

set -eu

BOTTLES="$HOME/Library/Application Support/CrossOver/Bottles"
BOTTLE="Battle.net Desktop App"
DLLS=""
MODE="install"

while [ $# -gt 0 ]; do
    case "$1" in
        --dlls)   DLLS="$2"; shift 2 ;;
        --bottle) BOTTLE="$2"; shift 2 ;;
        --verify) MODE="verify"; shift ;;
        --revert) MODE="revert"; shift ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

BOTTLE_DIR="$BOTTLES/$BOTTLE"
CONF="$BOTTLE_DIR/cxbottle.conf"

die() { echo "$*" >&2; exit 1; }

# --- the guard the header promises -------------------------------------------------
refuse_app_bundle() {
    case "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P || echo "$1")" in
        /Applications/*|/usr/local/*)
            die "refusing to write to $1 — this script only touches the bottle. See the header." ;;
    esac
}

case "$MODE" in
verify)
    P=$(pgrep -f '[O]verwatch\.exe' | head -1) || true
    [ -n "${P:-}" ] || die "Overwatch.exe is not running — start a match, then run --verify."
    echo "game pid $P"
    ours=$(lsof -p "$P" 2>/dev/null | grep -cE "$HOME/Library/Application Support/CrossOver/Bottles/.*/dxmt/" || true)
    theirs=$(lsof -p "$P" 2>/dev/null | grep -cE '/Applications/CrossOver\.app/.*/lib/dxmt/' || true)
    d3dm=$(lsof -p "$P" 2>/dev/null | grep -ci 'D3DMetal' || true)
    echo "  modules from the bottle (ours)      : $ours"
    echo "  modules from CrossOver.app (theirs) : $theirs"
    echo "  D3DMetal modules                    : $d3dm"
    if [ "$ours" -gt 0 ] && [ "$theirs" -eq 0 ]; then
        echo "OK — the game is running this pack's DXMT."
    elif [ "$theirs" -gt 0 ]; then
        echo "NOT OK — CrossOver's bundled DXMT won. Do not patch the bundle; open an issue."
        exit 1
    else
        echo "NOT OK — no DXMT modules at all. Check GraphicsAPI is DX11 in the game's video settings."
        exit 1
    fi
    ;;

revert)
    [ -f "$CONF.dxmt-ow2-pack.bak" ] || die "no backup at $CONF.dxmt-ow2-pack.bak"
    cp "$CONF.dxmt-ow2-pack.bak" "$CONF"
    echo "restored $CONF from the backup taken at install time."
    echo "the DLLs in $BOTTLE_DIR/dxmt are left alone; delete that directory if you want them gone."
    ;;

install)
    [ -n "$DLLS" ] || die "--dlls <dir> is required. See --help."
    for f in x86_64-windows/d3d11.dll x86_64-windows/dxgi.dll x86_64-windows/d3d10core.dll \
             x86_64-unix/winemetal.so; do
        [ -f "$DLLS/$f" ] || die "missing $f in $DLLS — is that a DXMT build directory?"
    done

    # One build, one directory. A mixed set (d3d11 from one build, dxgi from another) is the
    # single most reliable way to spend an evening on a bug that is not in the code. Only
    # d3d11.dll carries a version stamp, so the rest of the set is checked by build time: files
    # meson/ninja wrote in one run land within seconds of each other. A spread of days is what a
    # hand-assembled set looks like.
    stamp=$(strings "$DLLS/x86_64-windows/d3d11.dll" | grep -m1 -oE 'v0\.[0-9]+[-0-9a-z.]*' || true)
    [ -n "$stamp" ] || die "no version stamp in d3d11.dll — the stamp is generated at configure time; run 'meson setup --reconfigure' and rebuild."

    times=$(cd "$DLLS" && stat -f '%m' x86_64-windows/d3d11.dll x86_64-windows/dxgi.dll \
                              x86_64-windows/d3d10core.dll x86_64-unix/winemetal.so)
    oldest=$(echo "$times" | sort -n | head -1)
    newest=$(echo "$times" | sort -n | tail -1)
    spread=$((newest - oldest))
    if [ "$spread" -gt 600 ]; then
        echo "these four files were written $((spread / 60)) minutes apart:" >&2
        (cd "$DLLS" && ls -lT x86_64-windows/*.dll x86_64-unix/winemetal.so | awk '{print "  ", $6, $7, $8, $9, $NF}') >&2
        die "that is not one build directory. Rebuild all of DXMT from one commit and pass that directory."
    fi
    echo "DXMT build: $stamp (one build, files within ${spread}s of each other)"

    [ -d "$BOTTLE_DIR" ] || die "no such bottle: $BOTTLE_DIR"
    [ -f "$CONF" ] || die "no cxbottle.conf in $BOTTLE_DIR"


    DEST="$BOTTLE_DIR/dxmt"
    refuse_app_bundle "$DEST"
    rm -rf "$DEST"; mkdir -p "$DEST"
    cp -R "$DLLS/x86_64-windows" "$DLLS/x86_64-unix" "$DEST/"
    xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
    echo "installed into $DEST"
    (cd "$DEST" && find . -type f \( -name '*.dll' -o -name '*.so' \) -exec md5 {} \;) | sed 's/^/  /'

    HERE=$(cd "$(dirname "$0")" && pwd -P)
    cp "$HERE/dxmt.conf" "$BOTTLE_DIR/dxmt-ow2-pack.conf"
    mkdir -p "$BOTTLE_DIR/dxmt-logs"

    [ -f "$CONF.dxmt-ow2-pack.bak" ] || cp "$CONF" "$CONF.dxmt-ow2-pack.bak"

    # CX_GRAPHICS_BACKEND is deliberately NOT set to dxmt: that makes CrossOver inject DLL
    # overrides pointing at its own bundled lib/dxmt, which is exactly the copy we are not using.
    python3 - "$CONF" "$BOTTLE_DIR" <<'PY'
import re, sys
conf, bottle = sys.argv[1], sys.argv[2]
want = {
    "WINEDLLPATH": f"{bottle}/dxmt/x86_64-windows",
    "WINEDLLOVERRIDES": "dxgi,d3d11,d3d10core=n,b",
    "DXMT_CONFIG_FILE": f"{bottle}/dxmt-ow2-pack.conf",
    "DXMT_USE_DEFAULT_METAL_CACHE": "1",
    "DXMT_METALFX_SPATIAL_SWAPCHAIN": "1",
    "DXMT_LOG_LEVEL": "error",
    "DXMT_LOG_PATH": f"{bottle}/dxmt-logs",
}
text = open(conf, encoding="utf-8").read()
if "[EnvironmentVariables]" not in text:
    text += "\n[EnvironmentVariables]\n"
head, sep, rest = text.partition("[EnvironmentVariables]")
end = rest.find("\n[")
block, tail = (rest[:end], rest[end:]) if end != -1 else (rest, "")
for k, v in want.items():
    line = f'"{k}" = "{v}"'
    pat = re.compile(rf'^"{re.escape(k)}"\s*=.*$', re.M)
    block = pat.sub(line, block) if pat.search(block) else block.rstrip("\n") + "\n" + line + "\n"
# CrossOver would otherwise hand the game its own bundled DXMT.
block = re.sub(r'^"CX_GRAPHICS_BACKEND"\s*=.*$\n?', "", block, flags=re.M)
open(conf, "w", encoding="utf-8").write(head + sep + block + tail)
print(f"wired up {conf} (backup: {conf}.dxmt-ow2-pack.bak)")
PY

    cat <<EOF

Next:
  1. In the game's video settings keep Graphics API on DX11. DXMT has no D3D12 path,
     and on DX12 none of this applies at all.
  2. Start a match, then in another terminal:  $HERE/install-dxmt.sh --verify
  3. To undo:  $HERE/install-dxmt.sh --revert
EOF
    ;;
esac
