# Install

## What you need

- Apple Silicon Mac, macOS 26 or newer
- CrossOver 26.3 with a working Battle.net bottle and Overwatch installed in it
- Nothing else. The pack brings its own DXMT.

This pack does not ship a Wine engine, so CrossOver is required at runtime. The bottle may live
anywhere — an external volume is fine, and so is a name other than the default.

## Install

From an unpacked release:

```sh
bash setup.sh --preflight     # can this machine run it? answers, writes nothing
bash setup.sh                 # install
```

`--preflight` checks the machine, the pack's own files and the bottle, and reports what is
missing without leaving anything behind. It exits `0` when it is ready, `10` when the machine is
not (with the reason), `11` when the pack is already installed, `12` when the pack's own files do
not match the hashes it shipped with.

Two environment variables matter, and only if the defaults are wrong:

```sh
OW2_BOTTLE="Battle.net Desktop App"                       # a name...
OW2_BOTTLE="/Volumes/Games/Battle.net Desktop App"        # ...or a full path
SATORU_GAME_HOME="$HOME/ow2-pack"                         # where the pack installs itself
```

The bottle is resolved the way CrossOver resolves it: an absolute path is taken as the bottle, a
bare name is looked up in `CX_BOTTLE_PATH` and then in `~/Library/Application
Support/CrossOver/Bottles`.

### What it does to your machine

| Where | What |
|---|---|
| the pack home | the DXMT build, `dxmt.conf`, `ow2.sh`, `README-local.txt`, `logs/` |
| your bottle | one file edited — `cxbottle.conf`; the previous copy is kept as `cxbottle.conf.dxmt-ow2-pack.bak` |
| anywhere else | nothing |

In `cxbottle.conf` it sets `WINEDLLPATH` (pointing at the pack home, the directory that contains
both `x86_64-windows/` and `x86_64-unix/`), `WINEDLLOVERRIDES=dxgi,d3d11,d3d10core=n,b`,
`DXMT_CONFIG_FILE`, `DXMT_LOG_PATH`, `DXMT_USE_DEFAULT_METAL_CACHE` and
`DXMT_METALFX_SPATIAL_SWAPCHAIN`, and it **removes** `CX_GRAPHICS_BACKEND` — with that set,
CrossOver injects its own overrides pointing at its bundled `lib/dxmt`, which is the copy we are
not using.

Nothing is ever written inside `/Applications/CrossOver.app`.

### If you built DXMT yourself

```sh
./install-dxmt.sh --dlls <your meson install directory>
```

That directory is what `meson install` produces: `x86_64-windows/` with `d3d11.dll`, `dxgi.dll`,
`d3d10core.dll`, `winemetal.dll`, and `x86_64-unix/winemetal.so`. It checks that `d3d11.dll`
carries a version stamp and that the files came out of one build, stages them as the pack's
payload, and hands over to `setup.sh`.

## Play

```sh
~/ow2-pack/ow2.sh              # or wherever SATORU_GAME_HOME pointed
~/ow2-pack/ow2.sh --plain      # D3DMetal instead, for comparison
~/ow2-pack/ow2.sh --dry-run    # print what it would run, do nothing
```

Use `ow2.sh` rather than CrossOver's window, at least the first time. A bottle reads its
environment when a wine session starts, not when a program does, so launching into a session
that Battle.net left running would quietly use the settings from before the install — which
looks exactly like the pack doing nothing. `ow2.sh` refuses a busy bottle instead, and asks you
to quit the game and Battle.net first. It never kills anyone's session.

`--plain` takes this pack's block out of `cxbottle.conf` for one launch, puts
`CX_GRAPHICS_BACKEND=d3dmetal` in its place, and restores the file when the session ends —
including when you interrupt it. That is what makes the comparison honest: CrossOver's launcher
assigns every key in that section unconditionally, so exporting a variable would not have
changed anything.

## Uninstall

```sh
bash uninstall.sh --dry-run    # lists the home and its size, removes nothing
bash uninstall.sh              # removes the home, restores cxbottle.conf from the backup
```

The game, the bottle's contents and your Battle.net install are never touched.

## In the game

Keep **Graphics API on DX11** in the video settings. DXMT has no D3D12 path; on DX12 none of
this applies. Expect the graphics preset to reset the first time you launch after switching
backends — the game sees a different `GPUDeviceID` and treats the hardware as new.

`CaptureDisplaysForFullscreen` is worth having, and the winecfg checkbox does **not** set it
(it writes `X11 Driver\GrabFullscreen`, which `winemac.drv` never reads):

```sh
CX=/Applications/CrossOver.app/Contents/SharedSupport/CrossOver
"$CX/bin/wine" --bottle "Battle.net Desktop App" reg add \
  "HKCU\\Software\\Wine\\Mac Driver" /v CaptureDisplaysForFullscreen /d Y /f
```

## Verify

Start a match, then from another terminal:

```sh
./install-dxmt.sh --verify
```

It reads the running game's loaded modules and reports how many came from this pack's home, how
many from inside the bottle (an older layout), how many from CrossOver's bundle, and how many
are D3DMetal. You want the first number above zero and the rest at zero.

Two things this catches that guessing does not:

- **The backend cannot be read off `system32`.** After a backend switch, `d3d11.dll`, `dxgi.dll`
  and `d3d10core.dll` there are still Wine builtins — the switch is done with DLL overrides. Only
  the loaded modules of the **running game** tell you the truth, and the launcher is not the game.
- If CrossOver's bundled DXMT wins, the fix is not to patch the bundle. Open an issue.

## Undo just the bottle

```sh
./install-dxmt.sh --revert
```

Restores the `cxbottle.conf` backup and leaves the pack home alone — useful when you want the
game back on CrossOver's own backend without removing anything. `uninstall.sh` does both.

## Check that the shader cache is doing its job

DXMT keeps a persistent SQLite cache per executable:

```sh
ls -la "$(getconf DARWIN_USER_CACHE_DIR)/dxmt/Overwatch.exe/"
ps -Ao pid,time,comm | grep -i mtlcompiler | grep -v grep
```

Play, quit the game completely, start it again, and compare the compiler's accumulated CPU time.
For reference: D3DMetal on DX12 spent **8:59** of compiler CPU over 7:38 of play, growing
linearly. DXMT on DX11 with a warm cache spent **1.34 s** over 6:40.
