#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
[[ $EUID != 0 ]] || die 'Configure as your normal user, not sudo.'
umask 077
mkdir -p "$PRIVATE"
chmod 700 "$PRIVATE"
[[ ! -f $PRIVATE/settings ]] || private_check
TMP=$(mktemp "$PRIVATE/settings.XXXXXX")
trap 'rm -f "$TMP"' EXIT
ask() {
 local key=$1 label=$2 default=${3:-} secret=${4:-no} old='' val
 [[ ! -f $PRIVATE/settings ]] || old=$(get "$key")
 [[ -z $old ]] || default=$old
 while true; do
  printf '%s (Enter keeps existing/default; - clears optional): ' "$label" >&2
  if [[ $secret == yes ]]; then IFS= read -rs val; printf '\n' >&2; else IFS= read -r val; fi
  [[ -n $val ]] || val=$default
  [[ $val != - ]] || val=''
  if [[ $key == CONTACT_* || $key == CALLER_ID ]]; then
   val=${val// /}; val=${val//-/}
   [[ ! $val =~ ^[0-9]{9}$ ]] || val=+48$val
  fi
  if valid_value "$key" "$val"; then printf '%s=%s\n' "$key" "$val" >> "$TMP"; break; fi
  printf 'Invalid input (value hidden). Passwords: 16–128 characters, letters/digits or _+./@=-.\n' >&2
 done
}
ask PHONE_USER 'Handset SIP username [100]' 100
ask PHONE_MODE 'Handset mode: managed or existing [managed]' managed
if [[ $(sed -n 's/^PHONE_MODE=//p' "$TMP") != existing ]]; then
 ask PHONE_PASSWORD 'Handset password' '' yes
fi
ask TRANSPORT 'Existing PJSIP transport name (from pjsip show transports)'
ask MAX_SECONDS 'Maximum answered call seconds [1800]' 1800
ask RING_SECONDS 'Ring timeout seconds [30]' 30
ask PROVIDER_ENABLED 'Enable verified HaloNet account? yes/no [no]' no
for n in 201 202 203 204 205; do ask "CONTACT_$n" "Contact $n E.164 or Polish 9 digits (optional)"; done
# Retain provider fields even when temporarily disabling the trunk.
if [[ $(sed -n 's/^PROVIDER_ENABLED=//p' "$TMP") == yes ]]; then
 ask DOMAIN 'Verified provider SIP host[:port]'
 ask PROVIDER_USER 'Verified SIP authentication/client username'
 ask PROVIDER_PASSWORD 'Provider password' '' yes
 ask REGISTER 'Provider requires registration? yes/no' yes
 ask DIAL_FORMAT 'Verified dial format: e164, digits, or 00' e164
 ask CALLER_ID 'Verified outbound caller ID (E.164)'
 ask SEND_PAI 'Provider requires P-Asserted-Identity? yes/no' no
elif [[ -f $PRIVATE/settings ]]; then
 for key in DOMAIN PROVIDER_USER PROVIDER_PASSWORD REGISTER DIAL_FORMAT CALLER_ID SEND_PAI; do
  value=$(get "$key"); [[ -z $value ]] || printf '%s=%s\n' "$key" "$value" >> "$TMP"
 done
fi
mv "$TMP" "$PRIVATE/settings"
printf 'Private configuration saved. Media counts will be derived during deployment.\n'
