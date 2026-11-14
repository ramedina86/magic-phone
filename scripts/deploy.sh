#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
source "$ROOT/scripts/render.sh"
[[ ${1:-} == '' || ${1:-} == --dry-run ]] || die 'Usage: deploy.sh [--dry-run]'
[[ $EUID == 0 || ${1:-} == --dry-run ]] || die 'Run deployment with sudo; configure first as your normal user.'
umask 077
private_check
media
detect
modules
[[ -f $CONF/extensions.conf && -f $CONF/pjsip.conf ]] || die 'Existing extensions.conf/pjsip.conf required.'
[[ ! -L $CONF/extensions.conf && ! -L $CONF/pjsip.conf && ! -L $CONF/magic-phone ]] || die 'Symlinked deployment targets unsupported.'
for path in "$DATA/sounds" "$DATA/sounds/custom" "$SOUND"; do
 [[ ! -L $path ]] || die 'Symlinked audio target unsupported; review paths before deployment.'
done
for path in "$CONF/magic-phone" "$SOUND"; do
 if [[ -d $path && -n $(find "$path" -type l -print -quit) ]]; then
  die 'Symlinks inside owned deployment directories are unsupported.'
 fi
done
transport=$(cli "pjsip show transport $(get TRANSPORT)")
[[ $transport == *'bind'* ]] || die 'Choose an existing loaded transport.'
# Reject namespace/endpoint collisions outside our owned includes, including nested files.
phone_pattern="$(get PHONE_USER)|"
if [[ $(get PHONE_MODE) == existing ]]; then
 phone_pattern=''
 endpoint=$(cli "pjsip show endpoint $(get PHONE_USER)")
 [[ $endpoint =~ context[[:space:]]*:[[:space:]]*magic-phone ]] || die 'Existing endpoint must first be migrated to context magic-phone.'
 [[ $endpoint =~ allow_transfer[[:space:]]*:[[:space:]]*false ]] || die 'Disable transfers on the existing endpoint first.'
fi
while IFS= read -r -d '' f; do
 [[ $f == "$CONF/magic-phone/"* ]] && continue
 [[ $f != "$CONF/.magic-phone-"* ]] || continue
 if grep -Eq "^\[(${phone_pattern}magic-phone|magic-rotation|magic-family|magic-reject-inbound|magic-trunk[^]]*)\]" "$f"; then
  die 'Existing endpoint or magic namespace found outside owned files. Review/migrate it before deployment.'
 fi
done < <(find "$CONF" -name '*.conf' -type f -print0)
if [[ ${1:-} == --dry-run ]]; then
 printf 'Checks passed. Would back up roots and owned files, install includes/media, then reload. Private diff suppressed.\nConfig: %s\nAudio: %s\nAudiobooks: %s; music: %s\n' "$CONF" "$SOUND" "$BOOKS" "$MUSIC"
 exit 0
fi
command -v flock >/dev/null || die 'flock required (util-linux).'
exec 9>"$CONF/.magic-phone-deploy.lock"
flock -n 9 || die 'Another deployment is active.'
# Detect actual daemon account from its process, not the invoking sudo user.
pid=$(pgrep -xo asterisk) || die 'Cannot identify Asterisk process.'
AST_USER=$(ps -o user= -p "$pid" | tr -d ' ')
AST_GROUP=$(ps -o group= -p "$pid" | tr -d ' ')
[[ -n $AST_USER && -n $AST_GROUP ]] || die 'Cannot identify service account.'
BACKUP=$(mktemp -d "$CONF/.magic-phone-backup.XXXXXXXX")
chmod 700 "$BACKUP"
cp -p "$CONF/extensions.conf" "$CONF/pjsip.conf" "$BACKUP/"
[[ ! -d $CONF/magic-phone ]] || cp -a "$CONF/magic-phone" "$BACKUP/owned"
[[ ! -d $SOUND ]] || cp -a "$SOUND" "$BACKUP/audio"
printf '%s\n' "$SOUND" > "$BACKUP/audio-path"
STAGE=$(mktemp -d "$CONF/.magic-phone-stage.XXXXXXXX")
rollback() {
 local code=$?
 trap - EXIT
 if ((code != 0)); then
  cp -p "$BACKUP/extensions.conf" "$CONF/extensions.conf"
  cp -p "$BACKUP/pjsip.conf" "$CONF/pjsip.conf"
  rm -rf -- "$CONF/magic-phone"
  [[ ! -d $BACKUP/owned ]] || cp -a "$BACKUP/owned" "$CONF/magic-phone"
  rm -rf -- "$SOUND"
  [[ ! -d $BACKUP/audio ]] || cp -a "$BACKUP/audio" "$SOUND"
  cli 'dialplan reload' >/dev/null || true
  cli 'pjsip reload' >/dev/null || true
  warn "Deployment failed; files restored. Review service state. Backup: $BACKUP"
 fi
 rm -rf -- "$STAGE"
 exit "$code"
}
trap rollback EXIT
render "$STAGE"
install -d -o "$AST_USER" -g "$AST_GROUP" -m 750 "$CONF/magic-phone"
for f in extensions.conf settings.conf pjsip-private.conf; do
 install -o "$AST_USER" -g "$AST_GROUP" -m 640 "$STAGE/$f" "$CONF/magic-phone/$f"
done
for f in settings.conf extensions.conf; do
 line="#include $CONF/magic-phone/$f"
 grep -Fqx "$line" "$CONF/extensions.conf" || printf '\n%s\n' "$line" >> "$CONF/extensions.conf"
done
line="#include $CONF/magic-phone/pjsip-private.conf"
grep -Fqx "$line" "$CONF/pjsip.conf" || printf '\n%s\n' "$line" >> "$CONF/pjsip.conf"
for dir in welcome audiobooks music; do install -d -o "$AST_USER" -g "$AST_GROUP" -m 750 "$SOUND/$dir"; done
install -o "$AST_USER" -g "$AST_GROUP" -m 640 "$WELCOME" "$SOUND/welcome/placeholder.wav"
shopt -s nullglob
for dir in audiobooks music; do
 for f in "$ROOT/audio/$dir/"*.wav16; do install -o "$AST_USER" -g "$AST_GROUP" -m 640 "$f" "$SOUND/$dir/"; done
done
cli 'dialplan reload' > "$BACKUP/reload.log"
cli 'pjsip reload' >> "$BACKUP/reload.log"
# CLI exit status alone does not indicate whether Asterisk accepted configuration.
loaded=$(cli 'dialplan show magic-phone')
[[ $loaded == *'201'* && $loaded == *'103'* ]] || die 'Dialplan failed to load.'
endpoint=$(cli "pjsip show endpoint $(get PHONE_USER)")
[[ $endpoint == *'magic-phone'* ]] || die 'Handset endpoint failed to load.'
printf 'Deployed; no restart, no transport or AstDB changes. Backup: %s\n' "$BACKUP"
