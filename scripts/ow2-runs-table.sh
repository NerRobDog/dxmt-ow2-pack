#!/bin/sh
# Render ~/ow2-runs.csv (written by ow2-run.sh) as a markdown table.
CSV="${1:-$HOME/ow2-runs.csv}"
[ -f "$CSV" ] || { echo "no runs recorded yet at $CSV" >&2; exit 1; }
awk -F',' '
NR==1 {
  print "| run | backend | fps | gpu ms | interval ms | app GB | compiler s | cache MB | swap MB | cmpr MB | config |"
  print "|---|---|---|---|---|---|---|---|---|---|---|"
  next
}
{
  gsub(/"/,"",$15)
  printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", \
         $2,$3,$4,$5,$6,$7,$9,$10,$11,$12,$15
}' "$CSV"
