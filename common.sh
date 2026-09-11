# Shared by setup.sh, uninstall.sh and ow2.sh. Sourced, never run on its own.
#
# The contract is satoru's pack contract v1 (NerRobDog/satoru, docs/pack-contract.md).
# What it asks of this file: the exit codes below, and the rule that preflight writes
# nothing into the game home and touches nothing outside the unpacked pack.

E_PRECONDITION=10   # this machine is not ready — stderr is shown to the person
E_NOTHING=11        # nothing to do. This is a SUCCESS
E_BADPACK=12        # the pack's own files are not the ones it expects

die10() { printf '%s\n' "$*" >&2; exit $E_PRECONDITION; }
die12() { printf '%s\n' "$*" >&2; exit $E_BADPACK; }
die()   { printf '%s\n' "$*" >&2; exit 1; }

PACK_ROOT=$(cd "$(dirname "$0")" && pwd -P)

# satoru passes the home in. Run by hand, the pack picks one and says which.
pack_home() {
    if   [ -n "${SATORU_GAME_HOME:-}" ]; then printf '%s\n' "$SATORU_GAME_HOME"
    elif [ -n "${OW2_PACK_HOME:-}" ];    then printf '%s\n' "$OW2_PACK_HOME"
    else printf '%s\n' "$HOME/ow2-pack"; fi
}

logs_dir() {
    if [ -n "${SATORU_LOGS:-}" ]; then printf '%s\n' "$SATORU_LOGS"
    else printf '%s\n' "$(pack_home)/logs"; fi
}

cx_root() {
    root="${CX_ROOT:-/Applications/CrossOver.app/Contents/SharedSupport/CrossOver}"
    [ -x "$root/bin/wine" ] || return 1
    printf '%s\n' "$root"
}

# Resolve a bottle the way CrossOver resolves it (lib/perl/CXBottle.pm, find_bottle):
# for a private bottle an absolute path IS the name; otherwise the name is looked up
# in CX_BOTTLE_PATH, a colon-separated list of absolute paths, and failing that in the
# user's own bottle directory.
#
# Not pedantry: on one of our two machines the Battle.net bottle sits on an external
# volume and does not appear in the user's bottle directory at all.
resolve_bottle() {
    want="${1:-${OW2_BOTTLE:-Battle.net Desktop App}}"
    case "$want" in
        /*) [ -d "$want" ] || return 1; printf '%s\n' "$want"; return 0 ;;
    esac
    search="${CX_BOTTLE_PATH:-$HOME/Library/Application Support/CrossOver/Bottles}"
    saved_ifs=$IFS
    IFS=:
    for dir in $search; do
        IFS=$saved_ifs
        if [ -d "$dir/$want" ]; then printf '%s\n' "$dir/$want"; IFS=$saved_ifs; return 0; fi
        IFS=:
    done
    IFS=$saved_ifs
    return 1
}

# Busy means a wineserver holds THIS bottle's prefix. Never `pgrep wineserver`: this
# machine runs bottles for three other games, and refusing — or worse, killing — on
# someone else's session is a bigger failure than the one it prevents.
bottle_busy() {
    bottle="$1"
    command -v lsof >/dev/null 2>&1 || return 1
    lsof +D "$bottle/drive_c" 2>/dev/null | grep -q 'wineserver\|wine64\|Overwatch' && return 0
    return 1
}

# The five files that make a DXMT set. winemetal.dll is easy to forget and fatal to
# omit: the PE side of the unix library.
payload_files() {
    printf '%s\n' \
        dxmt/x86_64-windows/d3d11.dll \
        dxmt/x86_64-windows/dxgi.dll \
        dxmt/x86_64-windows/d3d10core.dll \
        dxmt/x86_64-windows/winemetal.dll \
        dxmt/x86_64-unix/winemetal.so
}

# A set has to come from one build. Inside a release that is settled before the
# download — satoru verifies the tarball by sha256, and make-pack.sh writes SHA256SUMS
# over every file — so this checks against those hashes. The mtime heuristic stays in
# install-dxmt.sh, which accepts a build directory a person assembled by hand, and
# where it is the only evidence available.
verify_payload() {
    root="${1:-$PACK_ROOT}"
    # The paths carry no spaces, so word splitting is the right tool here.
    for f in $(payload_files); do
        [ -f "$root/$f" ] || die12 "the pack is missing $f — download it again"
    done
    [ -f "$root/SHA256SUMS" ] || return 0
    sums=$(mktemp) || die "cannot create a temporary file"
    for f in $(payload_files); do
        grep -E "[[:space:]]\.?/?$f\$" "$root/SHA256SUMS" || true
    done > "$sums"
    if [ -s "$sums" ]; then
        ( cd "$root" && shasum -a 256 -c "$sums" >/dev/null 2>&1 ) || {
            rm -f "$sums"
            die12 "the DXMT files do not match the SHA256SUMS this pack shipped with — download it again"
        }
    fi
    rm -f "$sums"
}

# Only d3d11.dll carries a stamp, and it is generated at configure time from
# `git describe`, so a build nobody reconfigured has none.
build_id() {
    root="${1:-$PACK_ROOT}"
    strings "$root/dxmt/x86_64-windows/d3d11.dll" 2>/dev/null \
        | grep -m1 -oE 'v0\.[0-9]+[-0-9a-z.]*' || true
}

# Everything this pack writes into a bottle. Named once, used by setup, uninstall and
# by ow2.sh --plain, so the three can never disagree about what "our block" is.
OUR_KEYS="WINEDLLPATH WINEDLLOVERRIDES DXMT_CONFIG_FILE DXMT_USE_DEFAULT_METAL_CACHE
          DXMT_METALFX_SPATIAL_SWAPCHAIN DXMT_LOG_LEVEL DXMT_LOG_PATH"
