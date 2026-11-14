#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
PRIVATE=${MAGIC_PRIVATE:-$ROOT/.private}
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
cli() { "$AST" "${AST_ARGS[@]}" -rx "$1"; }
detect() {
 AST=${ASTERISK_BIN:-$(command -v asterisk || true)}
 [[ -n $AST && -x $AST ]] || die 'Asterisk missing; install/build Asterisk 22 separately.'
 AST_ARGS=(); [[ -z ${ASTERISK_CONFIG:-} ]] || AST_ARGS=(-C "$ASTERISK_CONFIG")
 [[ $("$AST" -V) == 'Asterisk 22.'* ]] || die 'Asterisk 22.x required.'
 local info
 info=$(cli 'core show settings') || die 'Cannot connect to Asterisk; check CLI socket permissions/service.'
 CONF=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Configuration directory:[[:space:]]*//p')
 DATA=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Data directory:[[:space:]]*//p')
 DBPATH=$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*Database:[[:space:]]*//p')
 [[ $CONF == /* && $DATA == /* && -d $CONF && -d $DATA ]] || die 'Cannot detect configuration/data directories from core show settings.'
 [[ $CONF != *[[:space:]\"\#]* && $DATA != *[[:space:]\"\#]* ]] || die 'Paths with whitespace/quotes/# are unsupported.'
 SOUND=$DATA/sounds/custom/magic-phone
}
modules() {
 local m out
 for m in chan_pjsip res_pjsip res_pjsip_authenticator_digest res_pjsip_registrar res_pjsip_outbound_authenticator_digest res_pjsip_outbound_registration pbx_config app_playback app_stack app_dial app_exec app_verbose func_db func_strings func_logic format_wav codec_g722 codec_ulaw codec_alaw codec_resample; do
  out=$(cli "module show like $m.so")
  [[ $out == *'1 modules loaded'* ]] || die "Required module not loaded: $m.so"
 done
}
get() { sed -n "s/^$1=//p" "$PRIVATE/settings"; }
valid_value() {
 local key=$1 val=$2
 case $key in
 PHONE_USER) [[ $val =~ ^[0-9]{1,12}$ ]] ;;
 PHONE_PASSWORD|PROVIDER_PASSWORD) [[ $val =~ ^[a-zA-Z0-9_+./@=-]{16,128}$ ]] ;;
 TRANSPORT|PROVIDER_USER) [[ $val =~ ^[a-zA-Z0-9_.-]+$ ]] ;;
 DOMAIN) [[ $val =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*(:[0-9]{1,5})?$ ]] ;;
 MAX_SECONDS) [[ $val =~ ^[1-9][0-9]{0,4}$ ]] && ((val <= 86400)) ;;
 RING_SECONDS) [[ $val =~ ^[1-9][0-9]{0,2}$ ]] && ((val <= 180)) ;;
 PROVIDER_ENABLED|REGISTER|SEND_PAI) [[ $val == yes || $val == no ]] ;;
 DIAL_FORMAT) [[ $val == e164 || $val == digits || $val == 00 ]] ;;
 CONTACT_20[1-5]|CALLER_ID) [[ -z $val || $val =~ ^\+[1-9][0-9]{7,14}$ ]] ;;
 *) return 1 ;;
 esac
}
private_check() {
 [[ -f $PRIVATE/settings && ! -L $PRIVATE/settings ]] || die 'Run configure.sh first.'
 local mode key val seen='|'
 mode=$(stat -c %a "$PRIVATE/settings" 2>/dev/null || stat -f %Lp "$PRIVATE/settings")
 [[ $mode == 600 ]] || die 'Private settings must have mode 0600.'
 while IFS='=' read -r key val; do
  [[ $seen != *"|$key|"* ]] || die 'Duplicate private setting.'
  seen+="$key|"
  valid_value "$key" "$val" || die "Invalid private setting: $key (value hidden)."
 done < "$PRIVATE/settings"
 for key in PHONE_USER PHONE_PASSWORD TRANSPORT MAX_SECONDS RING_SECONDS PROVIDER_ENABLED; do
  [[ -n $(get "$key") ]] || die "Missing $key"
 done
 if [[ $(get PROVIDER_ENABLED) == yes ]]; then
  for key in DOMAIN PROVIDER_USER PROVIDER_PASSWORD REGISTER DIAL_FORMAT SEND_PAI CALLER_ID; do
   [[ -n $(get "$key") ]] || die "Provider requires $key"
  done
 fi
}
media_file() {
 local file=$1 rate=$2 result
 command -v ffprobe >/dev/null || die 'Install ffmpeg (ffprobe) for media validation.'
 result=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$file") || die 'Unreadable audio.'
 [[ $result == "pcm_s16le,$rate,1" ]] || die "Audio must be mono PCM s16le at $rate Hz: $file"
 [[ $(ffprobe -v error -show_entries format=format_name -of csv=p=0 "$file") == wav ]] || die "WAV container required: $file"
}
count_media() {
 local dir=$1 n=0 f
 shopt -s nullglob dotglob
 for f in "$dir"/*; do
  [[ ${f##*/} == .gitkeep ]] && continue
  [[ -f $f && ! -L $f && ${f##*/} =~ ^[1-9][0-9]*\.wav16$ ]] || die "Invalid media filename: $f"
  media_file "$f" 16000
  n=$((n+1))
 done
 shopt -u nullglob dotglob
 for ((i=1;i<=n;i++)); do [[ -f $dir/$i.wav16 ]] || die "Playlist gap at $i in $dir"; done
 printf '%s\n' "$n"
}
media() {
 WELCOME=$ROOT/audio/welcome/greeting.wav
 [[ -f $WELCOME ]] || WELCOME=$ROOT/audio/welcome/placeholder.wav
 media_file "$WELCOME" 8000
 BOOKS=$(count_media "$ROOT/audio/audiobooks")
 MUSIC=$(count_media "$ROOT/audio/music")
 ((BOOKS > 0)) || warn 'Audiobooks empty: feature disabled.'
 ((MUSIC > 0)) || warn 'Music empty: feature disabled.'
}
