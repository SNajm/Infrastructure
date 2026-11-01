#!/usr/bin/env bash
# C001.261031T2215 — DSEP00.03: run the read-only discovery on both web servers.
# Usage (dev PC, Git Bash):  bash D:/repos/Infrastructure/Scripts/discover.sh
# Output is shown and saved to D:/Claude/scratch/Infrastructure/discovery-<host>.txt
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
key="D:/repos/.config/exchequer/exchequer-ssh.key"   # a key glyphadmin accepts on both servers (verified 2026-11-01)
out="D:/Claude/scratch/Infrastructure"
mkdir -p "$out"

for h in glyphscribe.crucible 10.10.15.30; do
  echo "########## $h"
  tr -d '\r' < "$here/server/discover-deploy-state.sh" \
    | ssh -i "$key" -o BatchMode=yes -o ConnectTimeout=10 "glyphadmin@$h" 'bash -s' 2>&1 \
    | tee "$out/discovery-$h.txt"
done
