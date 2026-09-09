# Third party

Nothing in this repository is a binary. What the installer puts into your bottle is DXMT, built
from source; this file says which source.

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

## When a release exists

A published release will name the exact commit of `NerRobDog/dxmt` it was built from, the tag on
that fork, and the sha256 of every file — the same rules the
[AoE IV pack](https://github.com/NerRobDog/dxmt-aoe4-pack) follows. All DLLs in one release come
from one commit and one build directory; a config key the shipped DLL does not know is a
packaging error, not a harmless extra.

## Not distributed, ever

- Game files of any kind.
- Shader caches. They are derived from Blizzard's content, and they stay on the machine that
  built them — even though they do transfer between machines and we use that internally.
