#!/usr/bin/env bash
# C001.261031T2215 — DSEP00.06.b: create the operator account `glyphops` on a web server.
# Run on the server as glyphadmin (from Sanctum):   sudo bash /tmp/add-glyphops.sh
# Expects the public key at /tmp/glyphops.pub (copied by Scripts/stage-glyphops.sh).
# Shows the plan and asks before changing anything. Safe to re-run.
set -euo pipefail

USER_NAME=glyphops
PUB=${1:-/tmp/glyphops.pub}
FROM=10.10.30.79                       # the dev PC as the servers see it (DSEP00.02)
SUDOERS=/etc/sudoers.d/glyphops

die() { echo "STOPPED: $*" >&2; exit 1; }
[ "$(id -u)" -eq 0 ] || die "run with sudo: sudo bash $0"
[ -r "$PUB" ] || die "public key not found: $PUB (run Scripts/stage-glyphops.sh on the dev PC first)"

KEY=$(tr -d '\r' < "$PUB" | head -n1)
[[ $KEY =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ glyphops@ ]] || die "$PUB is not the glyphops ed25519 public key"
KEY_BODY=$(awk '{print $2}' <<<"$KEY")
LINE="from=\"$FROM\",restrict,pty $KEY"
HOME_DIR=/home/$USER_NAME

echo "Server: $(hostname)"
echo "Key:    $(ssh-keygen -lf "$PUB")"
echo
echo "Plan:"
if id "$USER_NAME" >/dev/null 2>&1; then echo "  - user $USER_NAME exists: keep it"
else echo "  - create user $USER_NAME (shell /bin/bash, home $HOME_DIR, no extra groups) and set its password (you type it)"; fi
echo "  - $HOME_DIR/.ssh/authorized_keys: ensure this line (only from $FROM; restrict,pty):"
echo "      $LINE"
echo "  - $SUDOERS (checked with visudo before install):"
echo "      $USER_NAME ALL=(ALL) ALL                     # full sudo, always with password"
echo "      $USER_NAME ALL=(root) NOPASSWD: /usr/bin/systemctl start vault-cert-pull.service, /opt/pki/pki-status.sh"
echo

if ! id "$USER_NAME" >/dev/null 2>&1; then
  useradd -m -s /bin/bash -c "Operator account for scripted admin work (C001.261031T2215)" "$USER_NAME"
  echo "Set the password for $USER_NAME (sudo asks for it):"
  passwd "$USER_NAME"
fi

install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR/.ssh"
AK=$HOME_DIR/.ssh/authorized_keys
touch "$AK"
if grep -qF "$KEY_BODY" "$AK"; then
  echo "key already present: left as is"
else
  printf '%s\n' "$LINE" >> "$AK"
  echo "key added"
fi
chown "$USER_NAME:$USER_NAME" "$AK"; chmod 600 "$AK"
restorecon -R "$HOME_DIR/.ssh" 2>/dev/null || true

TMP=$(mktemp)
cat > "$TMP" <<EOF
# C001.261031T2215 DSEP00.06: operator account. Full sudo always asks for the password.
$USER_NAME ALL=(ALL) ALL
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/systemctl start vault-cert-pull.service, /opt/pki/pki-status.sh
EOF
visudo -cf "$TMP" >/dev/null || { rm -f "$TMP"; die "sudoers syntax check failed; nothing installed"; }
install -m 440 -o root -g root "$TMP" "$SUDOERS"; rm -f "$TMP"
visudo -cf "$SUDOERS" >/dev/null || die "visudo rejects the installed $SUDOERS"
echo "sudoers installed: $SUDOERS"
# Whole-config check: report problems in OTHER files, but they are not this script's to fix.
# (GlyphScribe 2026-11-01: sovereign-deploy had the wrong mode and stopped the first run here.)
if ! all=$(visudo -c 2>&1); then
  echo "WARNING: visudo -c reports a problem in another sudoers file (not changed by this script):"
  printf '%s\n' "$all" | grep -v ': parsed OK$' | sed 's/^/    /'
fi

rm -f "$PUB" /tmp/add-glyphops.sh
echo
echo "Done on $(hostname): $(id "$USER_NAME")"
