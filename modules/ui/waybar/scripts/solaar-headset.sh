#!/run/current-system/sw/bin/bash

set -eu

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$UID}"
cache_file="$runtime_dir/logitech-headset-battery/percent"
max_age_seconds="${HEADSET_CACHE_MAX_AGE_SECONDS:-300}"

if [ ! -r "$cache_file" ]; then
  printf '{"text":"N/A","tooltip":"Headset battery unavailable"}'
  exit 0
fi

if ! [[ "$max_age_seconds" =~ ^[0-9]+$ ]]; then
  max_age_seconds=300
fi

cache_mtime="$(stat -c '%Y' "$cache_file" 2>/dev/null || printf '0')"
now="$(date +%s)"
if [ "$cache_mtime" -le 0 ] || [ $((now - cache_mtime)) -gt "$max_age_seconds" ]; then
  printf '{"text":"N/A","tooltip":"Headset battery data is stale"}'
  exit 0
fi

value="$(tr -d '[:space:]' < "$cache_file")"
if ! [[ "$value" =~ ^[0-9]+$ ]]; then
  printf '{"text":"N/A","tooltip":"Headset battery unavailable"}'
  exit 0
fi

if [ "$value" -lt 0 ] || [ "$value" -gt 100 ]; then
  printf '{"text":"N/A","tooltip":"Headset battery unavailable"}'
  exit 0
fi

printf '{"text":"%s","percentage":%s,"tooltip":"Headset battery: %s%%"}' "$value" "$value" "$value"
