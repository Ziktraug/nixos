#!/run/current-system/sw/bin/bash

set -eu

best_capacity=""
best_name=""

for dir in /sys/class/power_supply/hidpp_battery_*; do
  [ -d "$dir" ] || continue

  capacity_file="$dir/capacity"
  name_file="$dir/model_name"

  [ -r "$capacity_file" ] || continue

  capacity="$(tr -d '[:space:]' < "$capacity_file")"
  if ! [[ "$capacity" =~ ^[0-9]+$ ]]; then
    continue
  fi

  name="Logitech device"
  if [ -r "$name_file" ]; then
    raw_name="$(tr -d '\n' < "$name_file")"
    if [ -n "$raw_name" ]; then
      name="$raw_name"
    fi
  fi

  if [[ "$name" == *"G502"* ]]; then
    best_capacity="$capacity"
    best_name="$name"
    break
  fi

  if [ -z "$best_capacity" ]; then
    best_capacity="$capacity"
    best_name="$name"
  fi
done

if [ -z "$best_capacity" ]; then
  printf '{"text":"N/A","tooltip":"Mouse battery unavailable"}'
  exit 0
fi

printf '{"text":"%s","percentage":%s,"tooltip":"%s: %s%%"}' "$best_capacity" "$best_capacity" "$best_name" "$best_capacity"
