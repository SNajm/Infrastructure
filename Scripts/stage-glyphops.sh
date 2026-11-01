#!/usr/bin/env bash
# C001.261031T2215 — DSEP00.06.b: copy add-glyphops.sh and the glyphops public key to /tmp on both
# web servers. Changes nothing else; the setup itself runs on the server (sudo, from Sanctum).
# Usage (dev PC, Git Bash):  bash D:/repos/Infrastructure/Scripts/stage-glyphops.sh
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
key="D:/repos/.config/exchequer/exchequer-ssh.key"   # still accepted by glyphadmin until DSEP07
pub="$HOME/.ssh/id_ed25519_glyphops.pub"
[ -r "$pub" ] || { echo "STOPPED: $pub not found. Create the key first (DSEP00.06.a)." >&2; exit 1; }

tmp=$(mktemp -d)
tr -d '\r' < "$here/server/add-glyphops.sh" > "$tmp/add-glyphops.sh"
tr -d '\r' < "$pub" > "$tmp/glyphops.pub"

for h in glyphscribe.crucible 10.10.15.30; do
  scp -q -i "$key" -o BatchMode=yes -o ConnectTimeout=10 "$tmp/add-glyphops.sh" "$tmp/glyphops.pub" "glyphadmin@$h:/tmp/" \
    && echo "staged on $h: /tmp/add-glyphops.sh, /tmp/glyphops.pub" \
    || echo "FAILED on $h"
done
rm -rf "$tmp"
echo "Next, in your Sanctum session on each server:  sudo bash /tmp/add-glyphops.sh"
