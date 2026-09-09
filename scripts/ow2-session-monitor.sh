#!/bin/bash
# One session monitor for Overwatch. Writes a memwatch v2 CSV: numeric MB, one row a minute.
#
#   memory only (no privileges):        ./ow2-session-monitor.sh
#   memory + GPU power and thermals:    sudo ./ow2-session-monitor.sh --pm
#
# OUT_DIR sets where the files land (default ~/ow2-telemetry). CHOWN_TO hands them back to a
# user when the script runs under sudo. It loops: waits up to 60 minutes for the game, records
# until the game exits, then waits for the next session.
set -u

WITH_PM=0
[ "${1:-}" = "--pm" ] && WITH_PM=1
if [ -z "${OUT_DIR:-}" ]; then
  OUT_DIR="$HOME/ow2-telemetry"
fi
mkdir -p "$OUT_DIR"

# The real game process: comm ends in Overwatch.exe. Battle.net.exe carries an Overwatch path
# in its arguments, so `pgrep -f` alone matches the launcher too.
find_game() {
  for P in $(pgrep -f "[O]verwatch\.exe"); do
    case "$(ps -o comm= -p "$P" 2>/dev/null)" in
      *Overwatch.exe) echo "$P"; return 0;;
    esac
  done
  return 1
}

# "5335 MB" / "876 KB" / "1.2 GB" -> numeric MB
to_mb() { awk -v v="$1" -v u="$2" 'BEGIN{ if(u=="KB")v/=1024; else if(u=="GB")v*=1024; printf "%.1f", v }'; }

while :; do
  echo "[monitor] waiting for Overwatch to start..."
  PID=""
  for i in $(seq 1 360); do
    PID=$(find_game) && break
    PID=""
    sleep 10
  done
  [ -z "$PID" ] && { echo "[monitor] no game for 60 minutes, exiting"; break; }
  TAG=$(date +%Y%m%d-%H%M)
  echo "[monitor] game pid=$PID, writing to $OUT_DIR (tag $TAG)"

  PMPID=""
  if [ "$WITH_PM" = 1 ]; then
    PM="$OUT_DIR/powermetrics-$TAG.txt"
    powermetrics --samplers gpu_power,thermal -i 60000 -o "$PM" &
    PMPID=$!
  fi

  MEM="$OUT_DIR/memwatch-$TAG.csv"
  {
    echo "# schema=memwatch v2"
    echo "# started=$(date +%Y-%m-%dT%H:%M:%S%z) host=$(hostname -s) pid=$PID"
    echo "ts,pid,footprint_mb,malloc_small_mb,swap_used_mb,swapouts"
  } > "$MEM"
  while kill -0 "$PID" 2>/dev/null; do
    TS=$(date +%H:%M:%S)
    FPOUT=$(footprint -p "$PID" 2>/dev/null)
    read -r FV FU <<< "$(echo "$FPOUT" | awk -F'Footprint: ' '/Footprint:/{split($2,a," "); print a[1], a[2]; exit}')"
    read -r MV MU <<< "$(echo "$FPOUT" | awk '/MALLOC_SMALL$/{print $1, $2; exit}')"
    FP=$([ -n "${FV:-}" ] && to_mb "$FV" "$FU" || echo "")
    MS=$([ -n "${MV:-}" ] && to_mb "$MV" "$MU" || echo "")
    SW=$(sysctl -n vm.swapusage | awk '{gsub(/M/,"",$6); print $6}')
    SO=$(vm_stat | awk '/Swapouts/{gsub(/\./,"");print $2}')
    echo "$TS,$PID,$FP,$MS,$SW,$SO" >> "$MEM"
    sleep 60
  done

  [ -n "$PMPID" ] && kill "$PMPID" 2>/dev/null
  [ -n "${CHOWN_TO:-}" ] && chown -R "$CHOWN_TO" "$OUT_DIR" 2>/dev/null
  echo "[monitor] game exited $(date +%H:%M:%S), waiting for the next one. Files: ${PM:-} $MEM"
done
