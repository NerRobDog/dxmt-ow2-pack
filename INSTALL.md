# Install

## What you need

- Apple Silicon Mac, macOS 26 or newer
- CrossOver 26.3 with a working Battle.net bottle and Overwatch installed in it
- A DXMT build from [`NerRobDog/dxmt`](https://github.com/NerRobDog/dxmt), branch `main`

There is no binary release of this pack yet, so the third item means building DXMT yourself.
The fork builds with meson + a mingw cross toolchain; an incremental build is about a minute
once the toolchain is set up. Run `meson setup --reconfigure` before the build you intend to
install — the version stamp inside `d3d11.dll` is generated at configure time, and
`install-dxmt.sh` refuses a set without one.

The build you pass in must contain, from one build directory:

```
x86_64-windows/d3d11.dll
x86_64-windows/dxgi.dll
x86_64-windows/d3d10core.dll
x86_64-unix/winemetal.so
```

## Install

```sh
./install-dxmt.sh --dlls /path/to/dxmt/build
```

The bottle defaults to `Battle.net Desktop App`; pass `--bottle "<name>"` for a different one.
The script:

1. checks that `d3d11.dll` carries a version stamp, and that all four files came out of one
   build (their timestamps must be within ten minutes of each other);
2. copies them into `<bottle>/dxmt/`, never into `/Applications/CrossOver.app`;
3. prints the md5 of each installed file;
4. backs up `cxbottle.conf` once, to `cxbottle.conf.dxmt-ow2-pack.bak`;
5. writes `WINEDLLPATH`, `WINEDLLOVERRIDES=dxgi,d3d11,d3d10core=n,b`, `DXMT_CONFIG_FILE`,
   `DXMT_USE_DEFAULT_METAL_CACHE=1`, `DXMT_METALFX_SPATIAL_SWAPCHAIN=1` and the log settings
   into the bottle's `[EnvironmentVariables]`, and **removes** `CX_GRAPHICS_BACKEND` — with it
   set to `dxmt`, CrossOver injects its own DLL overrides pointing at its bundled `lib/dxmt`,
   which is the copy we are not using.

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

It reads the running game's loaded modules and reports how many came from your bottle, how many
from CrossOver's bundle, and how many are D3DMetal. You want the first number above zero and the
other two at zero.

Two things this catches that guessing does not:

- **The backend cannot be read off `system32`.** After a backend switch, `d3d11.dll`, `dxgi.dll`
  and `d3d10core.dll` there are still Wine builtins — the switch is done with DLL overrides. Only
  the loaded modules of the **running game** tell you the truth, and the launcher is not the game.
- If CrossOver's bundled DXMT wins, the fix is not to patch the bundle. Open an issue.

## Undo

```sh
./install-dxmt.sh --revert
```

Restores the `cxbottle.conf` backup. The DLLs stay in `<bottle>/dxmt/`; delete that directory if
you want them gone.

## Check that the shader cache is doing its job

DXMT keeps a persistent SQLite cache per executable:

```sh
ls -la "$(getconf DARWIN_USER_CACHE_DIR)/dxmt/Overwatch.exe/"
ps -Ao pid,time,comm | grep -i mtlcompiler | grep -v grep
```

Play, quit the game completely, start it again, and compare the compiler's accumulated CPU time.
For reference: D3DMetal on DX12 spent **8:59** of compiler CPU over 7:38 of play, growing
linearly. DXMT on DX11 with a warm cache spent **1.34 s** over 6:40.
