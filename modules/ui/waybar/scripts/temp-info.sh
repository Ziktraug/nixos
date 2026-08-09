#!/run/current-system/sw/bin/bash
# Temperature monitoring script for Waybar

temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.0f", $1/1000}')

if [ -z "$temp" ]; then
    temp="N/A"
fi

# Get all sensor readings and format for JSON tooltip
tooltip=$(sensors 2>/dev/null | grep -E '°C|^[a-zA-Z].*:$' | grep -v '^$' | sed 's/  \+/ /g' | tr '\n' '|' | sed 's/|$//' | sed 's/|/\\n/g' | sed 's/"/\\"/g')

if [ -z "$tooltip" ]; then
    tooltip="No sensors found"
fi

printf '{"text":"%s", "tooltip":"%s"}' "$temp" "$tooltip"
