#!/bin/bash
# Build the release tarball for this pack — and refuse to build one that does not
# implement the contract its own game.toml declares.
#
#   tools/make-pack.sh <dxmt-build-dir> <version> [out-dir]
#
# <dxmt-build-dir> is what `meson install` produced for the DXMT build this release
# ships: x86_64-windows/ and x86_64-unix/. It is the only part not in git, because a
# DLL is not source. Everything else comes from the checked-out tree, so what ships is
# what is committed.
#
# Three things here are not decoration.
#
# COPYFILE_DISABLE=1: without it macOS tar writes an AppleDouble `._name` beside every
# entry whose file carries extended attributes. Those ship inside the tarball, and a
# `._pack` next to `pack/` makes the archive look multi-rooted to whatever unpacks it —
# satoru then runs the pack's commands one directory too high.
#
# The preflight gate: a manifest describes an artefact, not an intention. The AoE IV
# pack cut v0.1 before setup.sh learned --preflight and pointed a manifest declaring it
# at that release: a 139 MB download that ended in "unknown flag --preflight". This
# refuses to build a pack that cannot answer its own manifest.
#
# SHA256SUMS over every file: the set of DLLs has to come from one build, and inside a
# release that is what proves it. install checks against these, which is stronger than
# what it replaced — modification times say when files were copied, not where they came
# from.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DXMT="${1:-}"
VERSION="${2:-}"
OUT="${3:-$HERE/dist}"

die() { printf '%s\n' "$*" >&2; exit 1; }

[ -n "$DXMT" ] && [ -n "$VERSION" ] || die \
  "usage: tools/make-pack.sh <dxmt-build-dir> <version> [out-dir]
       dxmt-build-dir holds x86_64-windows/ and x86_64-unix/"
[ -d "$DXMT" ] || die "no such DXMT build directory: $DXMT"
[ -f "$HERE/game.toml" ] || die "no game.toml in $HERE — is this a pack?"
for part in x86_64-windows/d3d11.dll x86_64-windows/dxgi.dll x86_64-windows/d3d10core.dll \
            x86_64-windows/winemetal.dll x86_64-unix/winemetal.so; do
  [ -f "$DXMT/$part" ] || die "the DXMT build is incomplete: $DXMT/$part is missing"
done

STAMP="$(strings "$DXMT/x86_64-windows/d3d11.dll" | grep -m1 -oE 'v0\.[0-9]+[-0-9a-z.]*' || true)"
[ -n "$STAMP" ] || die "d3d11.dll carries no version stamp. It is generated at configure
time from git describe: run 'meson setup --reconfigure' on a tagged commit and rebuild."
echo "DXMT build: $STAMP"

# The repository's name, not the checkout's: as a satoru submodule this tree sits at
# games/ow2, and a tarball rooted at ow2/ with a URL to /ow2/releases would be wrong in
# both places.
ORIGIN="$(cd "$HERE" && git config --get remote.origin.url 2>/dev/null || true)"
NAME="$(basename -s .git "${ORIGIN:-$HERE}")"
STAGE="$(mktemp -d)/$NAME"
trap 'rm -rf "$(dirname "$STAGE")"' EXIT
mkdir -p "$STAGE"

echo "Staging tracked files..."
( cd "$HERE" && git ls-files -z ) | ( cd "$HERE" && xargs -0 -I{} \
  bash -c 'mkdir -p "$0/$(dirname "{}")" && cp -p "{}" "$0/{}"' "$STAGE" )

echo "Staging the DXMT build..."
rm -rf "${STAGE:?}/dxmt"
mkdir -p "$STAGE/dxmt"
cp -R "$DXMT/x86_64-windows" "$DXMT/x86_64-unix" "$STAGE/dxmt/"
# Import libraries are a build artefact, not a runtime one.
rm -f "$STAGE"/dxmt/x86_64-windows/*.a

echo "Hashing..."
( cd "$STAGE" && find . -type f ! -name SHA256SUMS -print0 \
    | sort -z | xargs -0 shasum -a 256 > SHA256SUMS )

# The gate. preflight is the one command the contract promises writes nothing into the
# home, so it is the one a build script may run. Exit 2 and 127 mean the pack did not
# understand what its own manifest declares; every other code is an answer — 10 on a
# machine with no CrossOver is a perfectly good answer.
PREFLIGHT="$(sed -n 's/^preflight[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
             "$HERE/game.toml" | head -1)"
if [ -n "$PREFLIGHT" ]; then
  echo "Asking the staged pack its own preflight: $PREFLIGHT"
  set +e
  ( cd "$STAGE" && SATORU_GAME_HOME="$(mktemp -d)" SATORU_CONTRACT=1 \
      bash -c "$PREFLIGHT" >/dev/null 2>&1 )
  code=$?
  set -e
  case "$code" in
    2|127) die "the staged pack answered $code to \`$PREFLIGHT\` — it does not implement
the manifest it ships with. Build refused: this is how a release ends up older than the
manifest pointing at it." ;;
    *) echo "  answered $code — understood, good enough to ship" ;;
  esac
fi

mkdir -p "$OUT"
TARBALL="$OUT/$NAME-$VERSION.tar.gz"
rm -f "$TARBALL"
echo "Building $TARBALL..."
COPYFILE_DISABLE=1 tar -czf "$TARBALL" -C "$(dirname "$STAGE")" "$NAME"

if tar -tzf "$TARBALL" | grep -q '^\._\|/\._'; then
  die "the tarball contains AppleDouble entries — COPYFILE_DISABLE did not take"
fi

SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
SIZE="$(wc -c < "$TARBALL" | tr -d ' ')"

echo
echo "built $TARBALL"
echo "  DXMT:   $STAMP"
echo "  sha256: $SHA"
echo "  size:   $SIZE bytes"
echo
echo "Publish the release FIRST, then paste this into game.toml:"
echo
echo "[source]"
echo "kind    = \"release\""
echo "url     = \"https://github.com/NerRobDog/$NAME/releases/download/$VERSION/$NAME-$VERSION.tar.gz\""
echo "sha256  = \"$SHA\""
echo "size    = $SIZE"
echo "version = \"$VERSION\""
