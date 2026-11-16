#!/usr/bin/env bash
# Run on the Pi: sudo bash /path/to/notes/deploy.sh
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Run with sudo.' >&2; exit 1; }
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
command -v python3 >/dev/null
command -v nginx >/dev/null
[[ -f /etc/nginx/sites-available/magic-phone ]] || { echo 'Expected existing placeholder nginx site.' >&2; exit 1; }
exec 9>/run/little-notes-deploy.lock
flock -n 9 || { echo 'Another deployment is running.' >&2; exit 1; }
umask 077
mkdir -p /var/backups/little-notes
BACKUP=$(mktemp -d /var/backups/little-notes/deploy.XXXXXXXX)
cp -a /etc/nginx/sites-available/magic-phone "$BACKUP/nginx.conf"
[[ ! -d /opt/little-notes ]] || cp -a /opt/little-notes "$BACKUP/code"
[[ ! -f /etc/systemd/system/little-notes.service ]] || cp -a /etc/systemd/system/little-notes.service "$BACKUP/service"
rollback() {
 result=$?
 trap - EXIT
 if ((result != 0)); then
  cp -a "$BACKUP/nginx.conf" /etc/nginx/sites-available/magic-phone
  systemctl stop little-notes.service || true
  if [[ -d $BACKUP/code ]]; then
   cp -a "$BACKUP/code/." /opt/little-notes/
  fi
  if [[ -f $BACKUP/service ]]; then
   cp -a "$BACKUP/service" /etc/systemd/system/little-notes.service
   systemctl daemon-reload
   systemctl restart little-notes.service || true
  else
   systemctl disable little-notes.service || true
  fi
  systemctl restart nginx || true
  echo "Deployment failed; previous website restored. Backup: $BACKUP" >&2
 fi
 exit "$result"
}
trap rollback EXIT
getent passwd littlenotes >/dev/null || useradd --system --user-group --home-dir /var/lib/little-notes --no-create-home --shell /usr/sbin/nologin littlenotes
install -d -m 755 /opt/little-notes /opt/little-notes/static
install -m 644 "$SOURCE/server.py" /opt/little-notes/server.py
for name in index.html api.html style.css app.js; do
 install -m 644 "$SOURCE/static/$name" "/opt/little-notes/static/$name"
done
install -m 644 "$SOURCE/notes.service" /etc/systemd/system/little-notes.service
systemctl daemon-reload
systemctl enable little-notes.service
systemctl restart little-notes.service
for attempt in {1..20}; do
 if python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8787/api/health", timeout=2).read()' 2>/dev/null; then break; fi
 sleep 1
done
python3 -c 'import urllib.request; assert urllib.request.urlopen("http://127.0.0.1:8787/api/health", timeout=5).status == 200'
install -m 644 "$SOURCE/nginx.conf" /etc/nginx/sites-available/magic-phone
nginx -t
# Restart permits changing the former address-specific listen socket.
systemctl restart nginx
python3 -c 'import urllib.request; assert b"little notes" in urllib.request.urlopen("http://127.0.0.1/", timeout=5).read()'
systemctl is-active little-notes nginx
printf 'Notes deployed. Website backup: %s\n' "$BACKUP"
