# dxmt-ow2-pack

Overwatch on Apple Silicon through **DXMT** — an open D3D11 → Metal translation layer — instead
of Apple's D3DMetal. Flat 60 fps, ~4 GB resident instead of 13 GB, and no swapping.

Part of [satoru](https://github.com/NerRobDog/satoru) — an open stack for running Windows games
on Apple Silicon.

> **Status: it installs itself, and it needs your CrossOver.** A release of this pack carries a
> DXMT build and installs it with one command; there is no Wine engine of its own, the way
> [dxmt-aoe4-pack](https://github.com/NerRobDog/dxmt-aoe4-pack) has one, so CrossOver with
> Battle.net and Overwatch in a bottle is what you bring. If you are reading this in the
> repository and the releases page is empty, build DXMT from
> [the fork](https://github.com/NerRobDog/dxmt) and use `./install-dxmt.sh --dlls` — same code,
> same result.

## What this changes

Two things, both measured on a MacBook Pro M1 Pro (16 GB) and a MacBook Air M5:

**The shader IR leak.** DXMT's shader translator kept every shader's parsed IR alive forever —
7.7 GB of live allocations, a game footprint of 13 GB, `MALLOC_SMALL` at 9.4 GB, and a machine
that swapped for the rest of the session. The `d3d11.releaseShaderIR` patch in
[our DXMT fork](https://github.com/NerRobDog/dxmt) frees the IR as soon as the shader is
created — reflection is extracted first and the DXBC copy kept — and rematerialises it only on
a cache miss.

| | stock DXMT v0.80 | with `releaseShaderIR` |
|---|---|---|
| game footprint | 13 GB | **3.8 GB** |
| `MALLOC_SMALL` | 9412 MB | **63 MB** |
| swapouts over a match | growing | **flat** |
| killcam | 22–28 fps | **59.9 fps** |

**Frame pacing.** `d3d11.preferredMaxFrameRate = 60` hands pacing to Metal/CoreAnimation and
turns a 38–87 fps sawtooth into a flat 16.67 ms line. We did not chase 120: the GPU ceiling in
fights is around 83 fps, and unstable 70–90 feels worse than steady 60.

Two things worth knowing before you tune anything yourself:

- **Practice Range lies.** 103 fps there, 55 fps typical in a real fight, 38.75 fps at its worst.
  It is a repeatable load for comparing knobs, and useless as a measure of playability.
- **In a fight you are not GPU-bound.** Across a whole match GPU time stays at 11.5–14.2 ms while
  the frame interval swings from 11.5 to 25.8 ms. In the worst frames the GPU finishes in 11.5 ms
  and the frame still takes 25.8. Cutting render scale, shadows or turning on MetalFX does not
  touch those 14 ms — they are not spent on the GPU.

## Reference configuration

[`dxmt.conf`](dxmt.conf), with the reasoning inline. The short version:

```ini
d3d11.preferredMaxFrameRate     = 60      # divisor of refresh rate, not a free-form cap
d3d11.releaseShaderIR           = True    # the 13 GB -> 3.8 GB fix; needs our fork
d3d11.metalSpatialUpscaleFactor = 1.33    # output upscale for sharpness, NOT a speed-up
d3d11.ignoreMapFlagNoWait       = False   # True fixes the killcam but adds constant micro-jitter
```

Plus `DXMT_METALFX_SPATIAL_SWAPCHAIN=1` and `DXMT_USE_DEFAULT_METAL_CACHE=1` in the environment;
the installer sets both. In the game, keep **Graphics API on DX11** — DXMT has no D3D12 path.

## Install

See [`INSTALL.md`](INSTALL.md). From an unpacked release:

```
bash setup.sh --preflight         # can this machine run it? writes nothing
bash setup.sh                     # install
./ow2.sh                          # play
./ow2.sh --plain                  # play on D3DMetal instead, for comparison
bash uninstall.sh --dry-run       # what removing it would take away
```

Built DXMT yourself? `./install-dxmt.sh --dlls <your meson install dir>` puts your build in the
pack and hands over to the same installer.

Where things land: the DLLs go into the pack's own home directory, and your bottle gets **one**
edited file, `cxbottle.conf`, pointing at them — the previous copy is kept beside it as
`cxbottle.conf.dxmt-ow2-pack.bak`. Nothing is written inside `/Applications/CrossOver.app`;
patching the application bundle breaks its code signature and the next CrossOver update silently
reverts it. The installer also refuses a DLL set that does not match the hashes the pack shipped
with — a mixed set is the most reliable way to spend an evening chasing a bug that is not in the
code.

Start the game through `ow2.sh` rather than from CrossOver's window the first time. A bottle
reads its environment when a wine session starts, so launching into a session Battle.net left
running quietly uses the settings from before the install.

## Measurement scripts

- `scripts/ow2-session-monitor.sh` — one row a minute: footprint, `MALLOC_SMALL`, swap used,
  swapouts. `--pm` adds GPU power and thermals (needs sudo).
- `scripts/ow2-run.sh` — record one benchmark run, machine-side metrics plus the Metal HUD
  numbers you read off the screen.
- `scripts/ow2-runs-table.sh` — render the recorded runs as a markdown table.

Note that `ps rss` lies here: it reported 268 MB at a moment when the Metal HUD said 14.35 GB.
It does not see Rosetta's address space or Metal's allocations. Use `footprint` or the HUD.

## Anti-cheat

Overwatch has one, and nothing here hides from it or interferes with it: this is a graphics
translation layer, the same category of thing as CrossOver's own backends.

What has actually been played, and on what: roughly **15 hours of matches in the first week**
since 2026-08-31, across a MacBook Pro M1 Pro and a MacBook Air M5, **on CrossOver's own Wine
engine** with this repository's DXMT and configuration on top — with **no account action taken**.

That is an observation about that setup, not a guarantee, and not a statement about Blizzard's
policy on running the game under Wine at all.

**It does not carry over to the standalone pack** described under "What is missing". That pack
would replace CrossOver's engine with a Wine build of our own, and how the anti-cheat treats a
different engine has not been tested. Until it has, the only configuration with hours behind it
is the bottle-based one on this page.

Play at your own risk.

## What is missing

- The bottle-side override path — `WINEDLLPATH` and `WINEDLLOVERRIDES` in `cxbottle.conf`, with
  `CX_GRAPHICS_BACKEND` deliberately removed — has **not** been confirmed on a running match yet.
  It could not have worked before: `WINEDLLPATH` named `<bottle>/dxmt/x86_64-windows`, one level
  below the directory wine actually searches, so it was looking for
  `x86_64-windows/x86_64-windows/d3d11.dll`. That is fixed, and unproven. `--verify`, run while a
  match is going, reads the game's loaded modules and tells you which DXMT got in. If CrossOver's
  bundled copy wins, open an issue rather than patching the bundle.
- A release is only cut after a build is accepted the way the AoE IV pack is: a clean install
  from the tarball, a match of 20 minutes or more with frametime p50/p95/p99 and memory at both
  ends, on both machines. A version number here is not a claim that someone played on it.
- No engine of our own, so CrossOver is still required at runtime. The AoE IV pack shows the
  shape this should take. Note that the anti-cheat evidence above was gathered on CrossOver's
  engine and says nothing about a different one — swapping the engine is a change that has to be
  tested on its own, cautiously, before anyone is told to run it.
- Shader caches are never distributed here: they are derived from Blizzard's content.

## Licenses

The scripts and documentation in this repository are MIT ([`LICENSE`](LICENSE)). DXMT is LGPL
([`LICENSE-DXMT-LGPL.txt`](LICENSE-DXMT-LGPL.txt)); see [`THIRD_PARTY.md`](THIRD_PARTY.md). No
game files and no shader caches are distributed here.

## Support

Free and open, and staying that way — see [`DONATE.md`](DONATE.md).
