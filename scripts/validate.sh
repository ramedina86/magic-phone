#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
private_check
media
[[ ${1:-} != --offline ]] || { printf 'Offline settings/media checks passed.\n'; exit 0; }
detect
modules
[[ -f $CONF/extensions.conf && -f $CONF/pjsip.conf ]] || die 'Existing root configuration files required.'
transport=$(cli "pjsip show transport $(get TRANSPORT)")
[[ $transport == *'protocol'* || $transport == *'bind'* ]] || die 'Configured transport not found.'
if [[ $(get PROVIDER_ENABLED) != yes ]]; then warn 'HaloNet disabled; local-only mode.'; fi
if [[ -d $CONF/magic-phone ]]; then
 for f in extensions.conf settings.conf pjsip-private.conf; do
  [[ -r $CONF/magic-phone/$f ]] || die "Missing/unreadable deployed include $f; run with appropriate CLI/config permissions."
 done
 grep -Fqx "#include $CONF/magic-phone/extensions.conf" "$CONF/extensions.conf" || die 'Missing dialplan include.'
 grep -Fqx "#include $CONF/magic-phone/settings.conf" "$CONF/extensions.conf" || die 'Missing settings include.'
 grep -Fqx "#include $CONF/magic-phone/pjsip-private.conf" "$CONF/pjsip.conf" || die 'Missing PJSIP include.'
 cmp -s "$ROOT/asterisk/extensions.conf" "$CONF/magic-phone/extensions.conf" || die 'Deployed dialplan differs; inspect before redeploy.'
 mode=$(stat -c %a "$CONF/magic-phone/pjsip-private.conf")
 [[ $mode == 640 || $mode == 600 ]] || die 'Unsafe deployed secret permissions.'
 endpoint=$(cli "pjsip show endpoint $(get PHONE_USER)")
 [[ $endpoint == *'magic-phone'* ]] || die 'Handset endpoint not loaded in magic-phone context.'
fi
printf 'Validation passed; use status.sh for registration state.\n'
