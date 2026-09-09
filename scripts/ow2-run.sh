#!/bin/sh
# Record one Overwatch/CrossOver benchmark run.
#
# Combines machine-side metrics (which the shell can see) with Metal HUD numbers
# (which only the player can read off the screen). Works on any backend --
# DXMT-only fields degrade to "-" under D3DMetal/DXVK.
#
# usage: ow2-run.sh <label> [fps] [gpu_ms] [frame_interval_ms] [app_mem_gb]
#   ow2-run.sh A-baseline 58.39 13.49 17.13 14.35
#   ow2-run.sh B-metalfx                 # HUD fields optional
#
# Appends a row to ~/ow2-runs.csv. Render it with ow2-runs-table.sh.
#
# Enable the HUD first: add "MTL_HUD_ENABLED" = "1" to the bottle's
# [EnvironmentVariables] block, then restart the game.

LABEL="$1"; FPS="${2:--}"; GPU="${3:--}"; INT="${4:--}"; APPMEM="${5:--}"
[ -z "$LABEL" ] && { echo "usage: $0 <label> [fps] [gpu_ms] [interval_ms] [app_gb]" >&2; exit 2; }

CSV="$HOME/ow2-runs.csv"
CD=$(getconf DARWIN_USER_CACHE_DIR)
P=$(pgrep -f "Overwatch.exe" | head -1)
[ -z "$P" ] && { echo "game not running" >&2; exit 1; }

ET=$(ps -o etime= -p "$P" | tr -d ' ')

# Cumulative CPU seconds across every Metal shader compiler process.
# Under a working shader cache this stays flat; without one it climbs linearly.
COMP=$(ps -Ao time,comm | grep -i mtlcompiler | grep -v grep \
       | awk '{n=split($1,a,":"); s+= (n==3? a[1]*3600+a[2]*60+a[3] : a[1]*60+a[2])} END{printf "%.2f", s+0}')

# Which backend is actually loaded. Do not trust system32 -- CrossOver attaches
# backends through DLL overrides, so the files there are Wine builtins regardless.
if   [ "$(lsof -p "$P" 2>/dev/null | grep -c 'lib/dxmt')" -gt 0 ]; then BACKEND=dxmt
elif [ "$(lsof -p "$P" 2>/dev/null | grep -c 'D3DMetal')" -gt 0 ]; then BACKEND=d3dmetal
elif [ "$(lsof -p "$P" 2>/dev/null | grep -c 'lib/dxvk')" -gt 0 ]; then BACKEND=dxvk
else BACKEND=wined3d; fi

# DXMT keeps a persistent SQLite shader cache; the other backends have none.
CACHE=$(du -sk "$CD/dxmt/Overwatch.exe" 2>/dev/null | awk '{printf "%.1f", $1/1024}')
[ -z "$CACHE" ] && CACHE="-"

SWAP=$(sysctl -n vm.swapusage | sed 's/.*used = //; s/M.*//')
CMPR=$(vm_stat | awk '/occupied by compressor/{gsub(/\./,"",$5); print int($5*16384/1048576)}')
SWAPOUT=$(vm_stat | awk '/Swapouts/{gsub(/\./,"",$2); print $2}')

GP=/Applications/Xcode.app/Contents/Developer/usr/bin/gamepolicyctl
if [ -x "$GP" ]; then
  GM=$("$GP" game-mode status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' \
       | sed -n 's/^Game mode is \([a-z]*\)\..*/\1/p' | head -1)
  [ -z "$GM" ] && GM="unknown"
else
  GM="no-xcode"
fi

CONF=$(grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$HOME/ow2-dxmt.conf" 2>/dev/null \
       | tr '\n' ';' | tr -d ',"')
[ -z "$CONF" ] && CONF="(defaults)"

[ -f "$CSV" ] || echo "ts,label,backend,fps,gpu_ms,frame_interval_ms,app_mem_gb,etime,compiler_cpu_s,shader_cache_mb,swap_mb,compressor_mb,swapouts,game_mode,dxmt_conf" > "$CSV"
printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
  "$(date '+%Y-%m-%d %H:%M:%S')" "$LABEL" "$BACKEND" "$FPS" "$GPU" "$INT" "$APPMEM" \
  "$ET" "$COMP" "$CACHE" "$SWAP" "$CMPR" "$SWAPOUT" "$GM" "$CONF" >> "$CSV"

echo "recorded: $LABEL  [$BACKEND]"
echo "  HUD      fps=$FPS gpu=${GPU}ms interval=${INT}ms app=${APPMEM}GB"
echo "  machine  etime=$ET compilerCPU=${COMP}s cache=${CACHE}MB"
echo "  memory   swap=${SWAP}MB compressor=${CMPR}MB swapouts=$SWAPOUT"
echo "  config   $CONF   gameMode=$GM"
