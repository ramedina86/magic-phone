#!/usr/bin/env bash
# Internal renderer, sourced by deploy after validation.
render() {
 local dest=$1 n number user transport
 user=$(get PHONE_USER); transport=$(get TRANSPORT)
 cp "$ROOT/asterisk/extensions.conf" "$dest/extensions.conf"
 {
  printf '[globals]\nMAGIC_AUDIOBOOKS=%s\nMAGIC_MUSIC=%s\n' "$BOOKS" "$MUSIC"
  printf 'MAGIC_PROVIDER=%s\nMAGIC_RING=%s\nMAGIC_LIMIT_MS=%s\n' "$(get PROVIDER_ENABLED)" "$(get RING_SECONDS)" "$(( $(get MAX_SECONDS) * 1000 ))"
  printf 'MAGIC_DIAL_FORMAT=%s\nMAGIC_CALLER_ID=%s\n' "$(get DIAL_FORMAT)" "$(get CALLER_ID)"
  for n in 201 202 203 204 205; do printf 'MAGIC_CONTACT_%s=%s\n' "$n" "$(get CONTACT_$n)"; done
 } > "$dest/settings.conf"
 {
 if [[ $(get PHONE_MODE) != existing ]]; then
 cat <<LOCAL
[$user]
type=endpoint
transport=$transport
context=magic-phone
disallow=all
allow=g722,ulaw,alaw
auth=magic-phone-auth
aors=$user
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
allow_transfer=no
allow_subscribe=no
set_var=TRANSFER_CONTEXT=magic-reject-inbound

[magic-phone-auth]
type=auth
auth_type=userpass
username=$user
password=$(get PHONE_PASSWORD)

[$user]
type=aor
max_contacts=1
remove_existing=yes
qualify_frequency=60
LOCAL
 fi
 if [[ $(get PROVIDER_ENABLED) == yes ]]; then
 cat <<TRUNK

[magic-trunk]
type=endpoint
transport=$transport
context=magic-reject-inbound
disallow=all
allow=ulaw,alaw,g722
outbound_auth=magic-trunk-auth
aors=magic-trunk-aor
from_user=$(get PROVIDER_USER)
from_domain=$(get DOMAIN)
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
allow_transfer=no
send_pai=$(get SEND_PAI)

[magic-trunk-auth]
type=auth
auth_type=userpass
username=$(get PROVIDER_USER)
password=$(get PROVIDER_PASSWORD)

[magic-trunk-aor]
type=aor
contact=sip:$(get DOMAIN)
TRUNK
 if [[ $(get REGISTER) == yes ]]; then
 cat <<REG

[magic-trunk-registration]
type=registration
transport=$transport
outbound_auth=magic-trunk-auth
server_uri=sip:$(get DOMAIN)
client_uri=sip:$(get PROVIDER_USER)@$(get DOMAIN)
retry_interval=60
REG
 fi
 fi
 } > "$dest/pjsip-private.conf"
}
