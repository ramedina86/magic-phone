# Little notes

A separate minimal LAN notes service, served at the Pi's root URL. Python 3 standard library + SQLite; no pip packages or frontend build. It does not modify Asterisk. The UI uses plain-text cards in aligned CSS grid rows. Highlighted notes retain date order.

Run locally: `python3 notes/server.py --port 8787 --db /tmp/little-notes-dev.sqlite3`. Open http://localhost:8787. Run tests: `python3 -m unittest discover -s notes/tests -v`.

API documentation is linked at `/api-docs`. No authentication: this is a shared notebook for trusted LAN devices. Do not forward the HTTP port publicly. Mutations require JSON and reject cross-origin browser requests. Text is inserted into the page as text, never HTML. Dates use UTC in storage and local time in the browser. The first page contains 100 notes; Load more retrieves older notes.

Deployment: code in `/opt/little-notes`, systemd unit `little-notes.service` running as an unprivileged `littlenotes` account, database in `/var/lib/little-notes/notes.sqlite3`, and nginx reverse proxy to loopback port 8787. The nginx listener uses port 80 on all local interfaces so DHCP address changes do not break it. No router/firewall changes are made. Logs: `sudo journalctl -u little-notes`. Restart: `sudo systemctl restart little-notes`.

Back up the database using SQLite's backup API rather than copying a live WAL database. For example, run Python as root and use `sqlite3.connect('/var/lib/little-notes/notes.sqlite3').backup(sqlite3.connect('/root/notes-backup.sqlite3'))`. Keep backup permissions restricted. Updates replace code only; they do not replace the data directory. To roll back the website, restore the prior nginx site file from the deployment backup and restart nginx; stop little-notes. Its database remains available.
