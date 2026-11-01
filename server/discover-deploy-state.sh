#!/usr/bin/env bash
# C001.261031T2215 — DSEP00.03 discovery. READ-ONLY: changes nothing, needs no password.
# Run from the dev PC, once per web server:
#   ssh -i <a key glyphadmin accepts> glyphadmin@<server> 'bash -s' < server/discover-deploy-state.sh
set -u
apps="ashborne exchequer sovereign ravenhold mimir"

section() { printf '\n===== %s\n' "$1"; }

section "host"
hostname; cat /etc/os-release 2>/dev/null | grep -E '^PRETTY_NAME='
echo "seen from: ${SSH_CLIENT%% *}"          # the address the server sees for this PC (for from=)

section "glyphadmin identity and groups"
id glyphadmin

section "app runtime groups (members)"
for a in $apps; do getent group "${a}mgr" "${a}" 2>/dev/null; done

section "existing deploy users"
for a in $apps; do getent passwd "${a}deploy" || echo "${a}deploy: none"; done

section "/opt ownership"
for a in $apps; do
  [ -d "/opt/$a" ] || { echo "/opt/$a: missing"; continue; }
  stat -c '%A %U:%G %n' "/opt/$a" "/opt/$a"/* 2>/dev/null | grep -vE '\.(dll|pdb|so|json\.br|gz)$' | head -40
done

section "sudoers drop-ins (names only)"
ls -l /etc/sudoers.d/ 2>&1

section "glyphadmin's no-password sudo rules"
sudo -n -l 2>&1

section "systemd units and timers that may write app files"
systemctl list-unit-files --no-pager 2>/dev/null | grep -Ei 'vault|cert|pki|ashborne|exchequer|sovereign|ravenhold|mimir'
for u in $(systemctl list-unit-files --no-pager --no-legend 2>/dev/null | awk '{print $1}' | grep -Ei 'vault|cert|pki'); do
  echo "--- $u"; systemctl cat "$u" 2>/dev/null | grep -E '^(User|Group|ExecStart|ReadWritePaths|OnCalendar)='
done

section "PKI config (paths only)"
ls -l /opt/pki 2>&1
grep -E '^\s*(pki_dest|pki_cert_name|owner|group|user)' /opt/pki/*.conf 2>/dev/null

section "glyphadmin crontab"
crontab -l 2>&1

section "listening ports"
ss -tlnp 2>/dev/null | awk 'NR==1 || /127\.0\.0\.1|0\.0\.0\.0|\[::\]/' | awk '{print $4}'
