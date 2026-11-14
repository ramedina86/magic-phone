# Magic Phone

A small Bash/Asterisk 22 configuration for a child's telephone on Raspberry Pi Zero 2 W, ARM64 Raspberry Pi OS / Debian Trixie. Requires an existing working Asterisk installation, an existing PJSIP transport, a SIP handset, Bash, coreutils, util-linux, and FFmpeg/ffprobe. No application server, call-time shell commands or database service.

| Dial | Action |
| --- | --- |
| 101 | “Hi Bob, your magic phone is working,” then hang up |
| 102 | One audiobook, rotating in order |
| 103 | One music track, rotating independently |
| 201 / 202 / 203 | Babcia / Mum / Dad, when configured |
| 204 / 205 | Optional private contacts |

## Quickstart

On the Pi, from this checkout:

```bash
./scripts/setup.sh
./scripts/configure.sh
./scripts/validate.sh
sudo ./scripts/deploy.sh --dry-run
sudo ./scripts/deploy.sh
./scripts/status.sh
```

If your normal user cannot access the Asterisk control socket, use sudo for setup, online validation and status too. Configure as your normal user. Scripts locate private data relative to the checkout, so sudo does not change which configuration is deployed. `ASTERISK_BIN`, `ASTERISK_CONFIG` and `MAGIC_PRIVATE` can explicitly select nonstandard installations; pass these explicitly through sudo when needed. `.env` is not sourced.

Setup discovers runtime directories through `core show settings` and checks loaded modules. It does not install software or change systemd. Select an existing transport by name; configure the handset with the Pi's current LAN address, selected transport's port/protocol, username (default 100), and password. A DHCP reservation is useful. Existing conflicting endpoint names cause deployment to stop for review; choose an unused username or manually migrate the old endpoint after backup.

Leave HaloNet disabled until account details are verified. All contacts may be blank in local-only mode. Nine-digit Polish inputs normalize to +48; other inputs must be E.164. Secrets are hidden during entry. Enter retains existing values; `-` clears optional values. Passwords accept 16–128 letters/digits or `_+./@=-`; unsupported provider credentials require a reviewed renderer extension, never a guessed replacement password.

## Audio and deployment

Put `1.wav16`, `2.wav16`, etc. in `audio/audiobooks/` or `audio/music/`. Replace the greeting using ignored `audio/welcome/greeting.wav`. See [audio formats](docs/audio-format.md). Counts are derived from validated contiguous files, never entered manually. Empty folders explicitly disable that playlist; enabled playlists always have positive counts. Deploy again to update counts/audio. Old deployed audio is retained but excluded from the new count. No automatic pruning is provided.

Deployment appends absolute includes once, backs up affected configuration and owned audio in a root-only `.magic-phone-backup.*` directory inside the detected Asterisk config directory, and reloads PJSIP/dialplan. It preserves transports, unrelated configuration and AstDB. Full audio backups require sufficient disk space. Dry-run checks inputs without displaying secrets. Runtime verification is limited; test calls on the Pi remain necessary. See [installation and rollback](docs/installation.md).

## Safety and diagnostics

This phone **is not a substitute for access to emergency services**. Emergency routing is out of scope; there is no internal 112 mapping. The handset context has only eight exact extensions, with no general outbound patterns. Transfers and SIP redirect following are disabled. Only five configured destinations can create paid calls; calls default to a 30-minute answered duration and 30-second ringing timeout. No alternate destination is tried on failure.

Keep SIP/RTP on the private LAN; remove temporary port forwards and disable router SIP ALG if it breaks signaling. Do not expose AMI/ARI. Restrict the host firewall and existing transport to trusted networks; deployment does not change firewall/listener settings. Audit other existing Asterisk endpoints/contexts separately. Ask HaloNet about prepaid/spending controls. Asterisk's own verbose logs/CDRs can contain phone numbers: protect those independently and avoid SIP packet logging with real credentials.

Use `scripts/status.sh`, `scripts/validate.sh`, and [troubleshooting](docs/troubleshooting.md). Private files, backups and all audio except the bundled spoken WAV are ignored. Do not commit logs or private configuration. Run `bash tests/run.sh` for host-independent configuration tests. Actual calls, codec negotiation and persistence must be tested on the Pi using the acceptance checklist.
