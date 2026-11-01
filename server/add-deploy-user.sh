#!/usr/bin/env bash
# C001.261031T2215 — DSEP01.02: per-app deploy user on a web server.
#
# Run on the server as glyphops (Scripts/deploy-user.ps1 copies this file and the key, then runs it):
#   sudo bash /tmp/add-deploy-user.sh <app> stage    create <app>deploy, key, group, sudoers. Old deploys keep working.
#   sudo bash /tmp/add-deploy-user.sh <app> take     /opt/<app>: glyphadmin's files -> <app>deploy. THE SWITCH:
#                                                    from here only <app>deploy can deploy the app.
#   sudo bash /tmp/add-deploy-user.sh <app> return   undo take: <app>deploy's files -> glyphadmin (rollback).
#
# Shows the plan and asks before changing anything. Safe to re-run. Every run is recorded in the journal
# (tag dsep: journalctl -t dsep).
set -euo pipefail

CHAT_ID=C001.261031T2215
FROM=10.10.30.79                       # the dev PC as the servers see it (DSEP00.02)
OLD_OWNER=glyphadmin

APP=${1:-}
MODE=${2:-}

log() { logger -t dsep -- "add-deploy-user.sh $CHAT_ID $*" 2>/dev/null || true; }
die() { echo "STOPPED: $*" >&2; log "FAILED ${APP:-?} ${MODE:-?}: $*"; exit 1; }

# Per-app facts (verified on the servers 2026-11-01, DSEP00.03). Service group = the app's runtime group.
# Sudo commands = today's glyphadmin rule for that app (§2.3), nothing more.
case "$APP" in
  exchequer) GROUP=excheqmgr;    EXTRA="" ;;
  ashborne)  GROUP=ashbornemgr;  EXTRA="" ;;   # cert install + nginx reload moved to glyphops (DSEP00.05)
  sovereign) GROUP=sovereignmgr; EXTRA="" ;;
  ravenhold) GROUP=ravenholdmgr; EXTRA=", /usr/bin/systemctl is-active ravenhold, /usr/bin/journalctl -u ravenhold -n 60 --no-pager" ;;
  mimir)     GROUP=mimirmgr;     EXTRA="" ;;
  *) die "usage: sudo bash $0 <exchequer|ashborne|sovereign|ravenhold|mimir> <stage|take|return>" ;;
esac
case "$MODE" in stage|take|return) ;; *) die "mode must be stage, take or return" ;; esac

[ "$(id -u)" -eq 0 ] || die "run with sudo: sudo bash $0 $APP $MODE"

DEPLOY_USER=${APP}deploy
APP_DIR=/opt/$APP
SUDOERS=/etc/sudoers.d/${DEPLOY_USER}
PUB=/tmp/${APP}-deploy.pub
RULE="$DEPLOY_USER ALL=(root) NOPASSWD: /usr/bin/systemctl start $APP, /usr/bin/systemctl stop $APP, /usr/bin/systemctl restart $APP, /usr/bin/systemctl status $APP$EXTRA"

getent group "$GROUP" >/dev/null || die "group $GROUP does not exist: set up the app's service user first (its deployment manual)"

# No confirmation: running the command is the decision (deployment-script standard).
confirm() { echo; echo "Applying..."; }

echo "Server: $(hostname)   App: $APP   Mode: $MODE   Run by: ${SUDO_USER:-root}"
echo

# ── stage ────────────────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = stage ]; then
  [ -r "$PUB" ] || die "public key not found: $PUB (Scripts/deploy-user.ps1 copies it)"
  KEY=$(tr -d '\r' < "$PUB" | head -n1)
  [[ $KEY =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ ${APP}-deploy@ ]] || die "$PUB is not the $APP deploy ed25519 public key"
  KEY_BODY=$(awk '{print $2}' <<<"$KEY")
  LINE="from=\"$FROM\",restrict $KEY"
  HOME_DIR=/home/$DEPLOY_USER
  AK=$HOME_DIR/.ssh/authorized_keys

  echo "Key: $(ssh-keygen -lf "$PUB")"
  echo "Plan:"
  if id "$DEPLOY_USER" >/dev/null 2>&1; then echo "  - user $DEPLOY_USER exists: keep it"
  else echo "  - create user $DEPLOY_USER (shell /bin/bash, home $HOME_DIR, no password: key login only)"; fi
  echo "  - groups: $GROUP only (removed from any other supplementary group)"
  echo "  - $AK: this one line (only from $FROM; restrict = no forwarding, no terminal):"
  echo "      $LINE"
  echo "  - $SUDOERS (checked with visudo before install):"
  echo "      $RULE"
  echo "  - nothing in $APP_DIR changes yet (that is 'take'); $OLD_OWNER can still deploy"
  confirm

  if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -c "$APP deploy user ($CHAT_ID)" "$DEPLOY_USER"
  fi
  usermod -G "$GROUP" "$DEPLOY_USER"           # -G without -a: exactly this supplementary group

  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$HOME_DIR/.ssh"
  touch "$AK"
  if grep -qF "$KEY_BODY" "$AK"; then echo "key already present: left as is"
  else printf '%s\n' "$LINE" >> "$AK"; echo "key added"; fi
  other=$(grep -cvF "$KEY_BODY" "$AK" || true)
  [ "$other" -eq 0 ] || echo "WARNING: $AK holds $other other line(s); a deploy user should have exactly one key"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$AK"; chmod 600 "$AK"
  restorecon -R "$HOME_DIR/.ssh" 2>/dev/null || true

  TMP=$(mktemp)
  printf '# %s DSEP: %s may start, stop and check %s only.\n%s\n' "$CHAT_ID" "$DEPLOY_USER" "$APP" "$RULE" > "$TMP"
  visudo -cf "$TMP" >/dev/null || { rm -f "$TMP"; die "sudoers syntax check failed; nothing installed"; }
  install -m 440 -o root -g root "$TMP" "$SUDOERS"; rm -f "$TMP"
  visudo -cf "$SUDOERS" >/dev/null || die "visudo rejects the installed $SUDOERS"
  echo "sudoers installed: $SUDOERS"

  for t in /tmp/${APP}-deploy.tar.gz /tmp/${APP}-deploy*.tar.gz; do
    [ -e "$t" ] && [ "$(stat -c %U "$t")" != "$DEPLOY_USER" ] \
      && echo "WARNING: $t is owned by $(stat -c %U "$t"); $DEPLOY_USER cannot replace it (sticky /tmp). Remove it before the first deploy."
  done
  rm -f "$PUB"
  log "SUCCESS $APP stage: $(id "$DEPLOY_USER")"
  echo; echo "Done: $(id "$DEPLOY_USER")"
  exit 0
fi

# ── take / return ────────────────────────────────────────────────────────────────────────────────
id "$DEPLOY_USER" >/dev/null 2>&1 || die "$DEPLOY_USER does not exist: run 'stage' first"
[ -d "$APP_DIR" ] || die "$APP_DIR does not exist on this server: nothing to take (the app's setup creates it owned by $DEPLOY_USER)"

if [ "$MODE" = take ]; then FROM_U=$OLD_OWNER; TO_U=$DEPLOY_USER; else FROM_U=$DEPLOY_USER; TO_U=$OLD_OWNER; fi

# Only entries owned by FROM_U change owner. root-owned certs (Vault PKI) and service-user folders
# (keys, data, logs where the service owns them) are left alone. Groups are kept, except files left in
# glyphadmin's own group, which move to the app group so the deploy user can manage them.
count=$(find "$APP_DIR" -xdev -user "$FROM_U" | wc -l)
gcount=$(find "$APP_DIR" -xdev -group "$OLD_OWNER" | wc -l)
echo "Plan:"
echo "  - $count entries under $APP_DIR owned by $FROM_U -> owner $TO_U (group unchanged)"
[ "$MODE" = take ] && [ "$gcount" -gt 0 ] && echo "  - $gcount entries in group $OLD_OWNER -> group $GROUP"
echo "  - left alone: anything owned by another user (root certs, the service user's folders)"
if [ "$MODE" = take ]; then echo "  - AFTER THIS only $DEPLOY_USER can deploy $APP; set its deploy.local.ps1 to $DEPLOY_USER"
else echo "  - AFTER THIS $OLD_OWNER deploys $APP again (rollback)"; fi
[ "$count" -gt 0 ] || { echo "nothing owned by $FROM_U: nothing to do"; log "SUCCESS $APP $MODE: nothing to do"; exit 0; }
confirm

find "$APP_DIR" -xdev -user "$FROM_U" -exec chown -h "$TO_U" {} +
[ "$MODE" = take ] && find "$APP_DIR" -xdev -group "$OLD_OWNER" -exec chgrp -h "$GROUP" {} +
left=$(find "$APP_DIR" -xdev -user "$FROM_U" | wc -l)
[ "$left" -eq 0 ] || die "$left entries still owned by $FROM_U"
log "SUCCESS $APP $MODE: $count entries -> $TO_U"
echo "Done: $count entries under $APP_DIR now owned by $TO_U"
