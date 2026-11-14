#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
private_check
detect
printf 'Asterisk 22 reachable.\n'
command -v systemctl >/dev/null && systemctl is-active asterisk.service || true
# Filter potentially sensitive CLI output, never print contact URIs/caller IDs.
out=$(cli "pjsip show aor $(get PHONE_USER)")
if [[ $out == *'Avail'* ]]; then
 printf 'Handset: reachable\n'
elif [[ $out == *'NonQual'* ]]; then
 printf 'Handset: registered (reachability probing disabled)\n'
else
 printf 'Handset: unavailable/unregistered\n'
fi
out=$(cli 'pjsip show registration magic-trunk-registration')
if [[ $out == *'Registered'* ]]; then printf 'Provider: registered\n'; else printf 'Provider: not registered (may be disabled or registration not required)\n'; fi
cli 'core show channels count' | grep -E '^[0-9]+ (active|calls)' || true
for key in audiobook_next music_next; do
 out=$(cli "database get magic $key")
 value=$(printf '%s\n' "$out" | sed -n 's/^Value: \([0-9]*\)$/\1/p')
 printf '%s: %s\n' "$key" "${value:-unset (starts at 1)}"
done
for dir in audiobooks music; do
 count=$(find "$SOUND/$dir" -maxdepth 1 -name '*.wav16' -type f 2>/dev/null | wc -l) || count=0
 printf '%s installed files: %s (stale files may be retained)\n' "$dir" "$count"
done
