# Third party

Nothing in this repository is a binary. A release of it is not so simple: the tarball carries a
built DXMT, because asking someone to set up a mingw cross toolchain before they can play is not
an install. This file says exactly which source that build came from, and the release names the
hash of every file it ships.

| Component | Upstream | Our fork | License |
|---|---|---|---|
| DXMT — D3D11/D3D10 → Metal | [3Shain/dxmt](https://github.com/3Shain/dxmt) | [NerRobDog/dxmt](https://github.com/NerRobDog/dxmt), branch `main` | LGPL 2.1 — [`LICENSE-DXMT-LGPL.txt`](LICENSE-DXMT-LGPL.txt) |

## What the fork adds over upstream, for this game

- `d3d11.releaseShaderIR` — frees a shader's parsed IR right after creation (reflection extracted
  first, the DXBC copy kept) and rematerialises it on a cache miss through `ir_ensure()`. A
  begin/end counter keeps it from being freed under a live user, and cross-shader participants
  (tessellation, geometry) are accounted for. This is the 13 GB → 3.8 GB fix.
- `dxgi.customVideoMemory` — caps the reported VRAM, the way DXVK's `maxDeviceMemory` does. Kept
  as a useful key; the hypothesis that the game's heap tracks the reported budget was tested and
  **disproved**, so it is not part of the reference configuration.

Nothing from this work goes upstream: 3Shain/dxmt does not accept AI-assisted contributions.
Findings are reported there as issue text, never as pull requests.

## What a release ships

The tarball contains, under `dxmt/`, five files from one build of
[NerRobDog/dxmt](https://github.com/NerRobDog/dxmt): `x86_64-windows/d3d11.dll`, `dxgi.dll`,
`d3d10core.dll`, `winemetal.dll` and `x86_64-unix/winemetal.so`. They are LGPL 2.1, the source is
the fork linked above, and the build is identified three ways that have to agree:

| | |
|---|---|
| commit | `8a9f4b749b3dce1f0340b7f92b4ce5d300d22421`, branch `main` |
| tag | `v0.80-ow2-0.3` |
| stamp inside `d3d11.dll` | `v0.80-ow2-0.3` — generated at configure time from `git describe` |

`SHA256SUMS` in the tarball covers every file in it, and `setup.sh` checks the five above against
it before installing anything. All of them come from one commit and one build directory: a mixed
set is the most reliable way to spend an evening on a bug that is not in the code. A config key
the shipped DLL does not know is a packaging error, not a harmless extra.

Building it yourself instead is supported and is the same code:
`./install-dxmt.sh --dlls <your meson install directory>`.

## Not distributed, ever

- Game files of any kind.
- Shader caches. They are derived from Blizzard's content, and they stay on the machine that
  built them — even though they do transfer between machines and we use that internally.
