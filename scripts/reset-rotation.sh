#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
case ${1:-} in audiobooks|music|all) ;; *) die 'Usage: reset-rotation.sh audiobooks|music|all';; esac
detect
if [[ $1 == audiobooks || $1 == all ]]; then cli 'database put magic audiobook_next 1'; fi
if [[ $1 == music || $1 == all ]]; then cli 'database put magic music_next 1'; fi
