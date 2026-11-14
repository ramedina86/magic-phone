#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/common.sh"
for f in "$ROOT"/scripts/*.sh; do bash -n "$f"; done
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PRIVATE=$TMP
cat > "$PRIVATE/settings" <<'SETTINGS'
PHONE_USER=100
PHONE_PASSWORD=abcdefghijklmnop
TRANSPORT=existing-udp
MAX_SECONDS=1800
RING_SECONDS=30
PROVIDER_ENABLED=no
CONTACT_201=
CONTACT_202=
CONTACT_203=
CONTACT_204=
CONTACT_205=
SETTINGS
chmod 600 "$PRIVATE/settings"
private_check
! valid_value CONTACT_201 '123&evil' || die 'Destination injection accepted'
! valid_value PHONE_PASSWORD 'abc;include=bad' || die 'Config injection accepted'
! valid_value MAX_SECONDS 0 || die 'Zero cap accepted'
! valid_value DOMAIN 'host/evil' || die 'URI injection accepted'
source "$ROOT/scripts/render.sh"
BOOKS=3 MUSIC=2
mkdir "$TMP/rendered"
render "$TMP/rendered"
grep -q '^MAGIC_LIMIT_MS=1800000$' "$TMP/rendered/settings.conf"
grep -q '^aors=100$' "$TMP/rendered/pjsip-private.conf"
! grep -q '^\[magic-trunk\]' "$TMP/rendered/pjsip-private.conf"
! grep -Eq '^exten => (_|112,)' "$ROOT/asterisk/extensions.conf"
[[ $(grep -c '^exten =>' "$ROOT/asterisk/extensions.conf") == 11 ]]
# Use actual media decoder when installed; offline rendering remains testable elsewhere.
if command -v ffprobe >/dev/null; then media; else warn 'ffprobe unavailable; media decode test skipped.'; fi
printf 'Shell syntax, validation boundaries, local-only rendering and dialplan route checks passed.\n'
# Exercise provider generation with synthetic data confined to a temporary directory.
sed 's/PROVIDER_ENABLED=no/PROVIDER_ENABLED=yes/' "$PRIVATE/settings" > "$TMP/new"
mv "$TMP/new" "$PRIVATE/settings"
cat >> "$PRIVATE/settings" <<'SETTINGS'
DOMAIN=example.invalid
PROVIDER_USER=test-user
PROVIDER_PASSWORD=abcdefghijklmnop
REGISTER=yes
DIAL_FORMAT=digits
CALLER_ID=+12025550123
SEND_PAI=no
SETTINGS
chmod 600 "$PRIVATE/settings"
private_check
render "$TMP/rendered"
grep -q '^server_uri=sip:example.invalid$' "$TMP/rendered/pjsip-private.conf"
grep -q '^context=magic-reject-inbound$' "$TMP/rendered/pjsip-private.conf"
grep -q '^MAGIC_DIAL_FORMAT=digits$' "$TMP/rendered/settings.conf"
printf 'Provider rendering passed using synthetic example.invalid data.\n'
printf 'PHONE_MODE=existing\n' >> "$PRIVATE/settings"
private_check
render "$TMP/rendered"
! grep -q '^\[100\]' "$TMP/rendered/pjsip-private.conf"
! grep -q '^\[magic-phone-auth\]' "$TMP/rendered/pjsip-private.conf"
printf 'Existing handset mode preserves external endpoint/auth configuration.\n'
