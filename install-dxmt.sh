#!/bin/bash
# dxmt-ow2-pack — the bring-your-own-build path, and the check that matters.
#
#   ./install-dxmt.sh --dlls <dir> [--bottle NAME|PATH]   install a DXMT build you compiled
#   ./install-dxmt.sh --verify                            check a RUNNING game loaded ours
#   ./install-dxmt.sh --revert  [--bottle NAME|PATH]      restore the bottle's config backup
#
# <dir> is a DXMT build directory holding x86_64-windows/{d3d11,dxgi,d3d10core,winemetal}.dll
# and x86_64-unix/winemetal.so — what `meson install` produces. Build it from
# https://github.com/NerRobDog/dxmt (branch main).
#
# A release of this pack carries a build already, and `bash setup.sh` installs that one.
# This script exists for the other case: you built DXMT yourself and want the pack to use
# it. It stages your build as the pack's payload and hands over to setup.sh, so there is
# one installer and not two that can disagree.
#
# It never writes inside /Applications/CrossOver.app. Dropping DLLs into the application
# bundle breaks its signature, and the next CrossOver update silently reverts it.
set -eu
. "$(cd "$(dirname "$0")" && pwd -P)/common.sh"

MODE=install
DLLS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dlls)   DLLS="$2"; shift 2 ;;
        --bottle) OW2_BOTTLE="$2"; export OW2_BOTTLE; shift 2 ;;
        --verify) MODE=verify; shift ;;
        --revert) MODE=revert; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
done

HOME_DIR=$(pack_home)

case "$MODE" in
verify)
    # Which DXMT the running game actually loaded. Do not trust the bottle's system32:
    # CrossOver attaches backends through DLL overrides, so what is on disk there says
    # nothing about what is mapped.
    P=$(pgrep -f '[O]verwatch\.exe' | head -1) || true
    [ -n "${P:-}" ] || die10 "Overwatch.exe is not running — start a match, then run --verify."
    printf 'game pid %s\n' "$P"
    mods=$(lsof -p "$P" 2>/dev/null || true)
    ours=$(printf '%s\n' "$mods" | grep -cF "$HOME_DIR/dxmt" || true)
    bottled=$(printf '%s\n' "$mods" | grep -cE '/Bottles/[^/]*/dxmt/' || true)
    theirs=$(printf '%s\n' "$mods" | grep -cE '/Applications/CrossOver\.app/.*/lib/dxmt/' || true)
    d3dm=$(printf '%s\n' "$mods" | grep -ci 'D3DMetal' || true)
    printf '  modules from this pack (%s) : %s\n' "$HOME_DIR/dxmt" "$ours"
    printf '  modules from inside a bottle      : %s\n' "$bottled"
    printf '  modules from CrossOver.app        : %s\n' "$theirs"
    printf '  D3DMetal modules                  : %s\n' "$d3dm"
    if [ "$ours" -gt 0 ] && [ "$theirs" -eq 0 ] && [ "$d3dm" -eq 0 ]; then
        printf 'OK — the game is running this pack DXMT.\n'
    elif [ "$theirs" -gt 0 ]; then
        printf 'NOT OK — CrossOver bundled DXMT won. Do not patch the bundle; open an issue.\n' >&2
        exit 1
    elif [ "$bottled" -gt 0 ]; then
        printf 'NOT OK — an older install left DLLs inside the bottle and they won. Run
uninstall.sh, delete <bottle>/dxmt, then install again.\n' >&2
        exit 1
    else
        printf 'NOT OK — no DXMT at all. Check Graphics API is DX11 in the game video settings,
and that the game was started after the last install (the bottle reads its settings when a
wine session starts).\n' >&2
        exit 1
    fi
    ;;

revert)
    BOTTLE=$(resolve_bottle "${OW2_BOTTLE:-}") || die10 "no such bottle: ${OW2_BOTTLE:-Battle.net Desktop App}"
    BAK="$BOTTLE/cxbottle.conf.dxmt-ow2-pack.bak"
    [ -f "$BAK" ] || die10 "no backup at $BAK"
    cp "$BAK" "$BOTTLE/cxbottle.conf"
    printf 'restored %s/cxbottle.conf from the backup taken at install time.\n' "$BOTTLE"
    printf 'The pack home at %s is left alone; uninstall.sh removes it.\n' "$HOME_DIR"
    ;;

install)
    [ -n "$DLLS" ] || die10 "--dlls <dir> is required. See --help."
    for f in $(payload_files); do
        [ -f "$DLLS/${f#dxmt/}" ] || die10 "missing ${f#dxmt/} in $DLLS — is that a DXMT install directory?"
    done

    # One build, one directory. Only d3d11.dll carries a version stamp, so the rest of a
    # hand-assembled set is judged by when it was written: files one build wrote land
    # together, and a spread of days is what a set assembled by hand looks like. A release
    # does not need this — it ships SHA256SUMS and satoru checks the tarball — but a
    # directory somebody put together by hand has nothing else to go on.
    stamp=$(strings "$DLLS/x86_64-windows/d3d11.dll" | grep -m1 -oE 'v0\.[0-9]+[-0-9a-z.]*' || true)
    [ -n "$stamp" ] || die10 "no version stamp in d3d11.dll — it is generated at configure time;
run 'meson setup --reconfigure' and rebuild."
    times=$(cd "$DLLS" && stat -f '%m' x86_64-windows/d3d11.dll x86_64-windows/dxgi.dll \
                              x86_64-windows/d3d10core.dll x86_64-windows/winemetal.dll \
                              x86_64-unix/winemetal.so)
    oldest=$(printf '%s\n' "$times" | sort -n | head -1)
    newest=$(printf '%s\n' "$times" | sort -n | tail -1)
    spread=$((newest - oldest))
    if [ "$spread" -gt 600 ]; then
        printf 'those files were written %s minutes apart:\n' "$((spread / 60))" >&2
        (cd "$DLLS" && ls -lT x86_64-windows/*.dll x86_64-unix/winemetal.so | awk '{print "  ", $6, $7, $8, $9, $NF}') >&2
        die10 "that is not one build directory. Rebuild all of DXMT from one commit."
    fi
    printf 'DXMT build: %s (one directory, files within %ss of each other)\n' "$stamp" "$spread"

    # Stage it as the pack payload, then let the one installer do the installing.
    rm -rf "$PACK_ROOT/dxmt"
    mkdir -p "$PACK_ROOT/dxmt"
    cp -R "$DLLS/x86_64-windows" "$DLLS/x86_64-unix" "$PACK_ROOT/dxmt/"
    rm -f "$PACK_ROOT/dxmt"/x86_64-windows/*.a
    ( cd "$PACK_ROOT" && shasum -a 256 $(payload_files) > SHA256SUMS )
    exec bash "$PACK_ROOT/setup.sh"
    ;;
esac
