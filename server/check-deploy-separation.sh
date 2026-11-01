#!/usr/bin/env bash
# C001.261031T2215 — DSEP01.03: prove an app's deploy user can touch only its own app.
# Runs AS <app>deploy (Scripts/check-separation.ps1 pipes it over ssh):  bash -s <app>
# READ-ONLY towards other apps: sudo rights are queried with `sudo -n -l <cmd>`, which never runs the
# command. The only write is a test file in the app's own folder, removed straight away.
set -u
CHAT_ID=C001.261031T2215
APPS="exchequer ashborne sovereign ravenhold mimir"
declare -A GROUP=([exchequer]=excheqmgr [ashborne]=ashbornemgr [sovereign]=sovereignmgr [ravenhold]=ravenholdmgr [mimir]=mimirmgr)

APP=${1:-}
[ -n "${GROUP[$APP]:-}" ] || { echo "usage: bash -s <app>"; exit 2; }
ME=$(id -un)
fails=0; passes=0
pass() { printf 'PASS  %s\n' "$*"; passes=$((passes+1)); }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }
info() { printf 'INFO  %s\n' "$*"; }
allowed() { sudo -n -l "$@" >/dev/null 2>&1; }    # 0 = sudo would allow it without a password

echo "Server: $(hostname)   App: $APP   User: $ME   ($CHAT_ID)"

# ── who am I ──
[ "$ME" = "${APP}deploy" ] && pass "running as ${APP}deploy" || fail "running as $ME, expected ${APP}deploy"
groups_now=$(id -Gn)
extra=$(tr ' ' '\n' <<<"$groups_now" | grep -vxE "${APP}deploy|${GROUP[$APP]}" || true)
[ -z "$extra" ] && pass "groups: $groups_now" || fail "extra groups: $extra"

# ── my own app ──
if [ -d "/opt/$APP" ]; then
  t="/opt/$APP/.dsep-check-$$"
  if touch "$t" 2>/dev/null; then rm -f "$t"; pass "can write /opt/$APP"
  elif [ "$(stat -c %U "/opt/$APP")" != "$ME" ]; then info "/opt/$APP is still owned by $(stat -c %U "/opt/$APP") ('take' not run yet)"
  else fail "cannot write /opt/$APP although it is owned by $ME"; fi
else
  info "/opt/$APP does not exist on this server yet"
fi
for c in start stop restart status; do
  allowed /usr/bin/systemctl "$c" "$APP" && pass "sudo systemctl $c $APP allowed" || fail "sudo systemctl $c $APP NOT allowed"
done
allowed /usr/bin/true && fail "unrestricted sudo (ran /usr/bin/true)" || pass "no general sudo"
allowed /usr/bin/systemctl reload nginx && fail "may reload nginx (admin work, glyphops)" || pass "no nginx reload"

# ── every other app ──
for o in $APPS; do
  [ "$o" = "$APP" ] && continue
  for c in start stop restart; do
    allowed /usr/bin/systemctl "$c" "$o" && fail "sudo systemctl $c $o allowed" || pass "sudo systemctl $c $o refused"
  done
  [ -d "/opt/$o" ] || { info "/opt/$o not on this server"; continue; }
  t="/opt/$o/.dsep-check-$$"
  if touch "$t" 2>/dev/null; then rm -f "$t"; fail "can write /opt/$o"; else pass "cannot write /opt/$o"; fi
  readable=""
  for f in /opt/"$o"/appsettings*.json /opt/"$o"/app/.env* /opt/"$o"/.env*; do
    [ -e "$f" ] && head -c1 "$f" >/dev/null 2>&1 && readable="$readable $f"
  done
  [ -z "$readable" ] && pass "cannot read $o's settings" || fail "can read:$readable"
done

echo
echo "Result: $passes passed, $fails failed"
[ "$fails" -eq 0 ]
