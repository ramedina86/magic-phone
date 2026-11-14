#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $(uname -s) == Linux ]] || die 'Deployment target must be Linux.'
[[ $(uname -m) == aarch64 ]] || warn 'Target is intended to be ARM64 Raspberry Pi Zero 2 W.'
if [[ -f /etc/os-release ]]; then
 grep -Eq '^VERSION_CODENAME=trixie$' /etc/os-release || warn 'Expected Debian/Raspberry Pi OS Trixie.'
fi
detect
modules
command -v ffprobe >/dev/null || die 'Install ffmpeg for audio validation.'
printf 'Asterisk 22 reachable. Config: %s\nSounds: %s\nAstDB: %s (never modified by deploy)\n' "$CONF" "$SOUND" "$DBPATH"
if command -v systemctl >/dev/null; then
 systemctl list-units --type=service --all --no-pager 'asterisk*' || true
fi
printf 'Existing transports (choose one in configure.sh):\n'
cli 'pjsip show transports'
printf 'No system files changed. Deployment prepares owned directories.\n'
