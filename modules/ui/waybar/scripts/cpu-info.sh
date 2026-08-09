#!/run/current-system/sw/bin/bash
# CPU monitoring script for Waybar

cpu=$(awk '/^cpu / {usage=100-($5*100/($2+$3+$4+$5+$6+$7+$8)); printf "%.0f", usage}' /proc/stat)

# Try different sensor labels (AMD uses Tctl, Intel uses Package id 0 or Core 0)
temp=$(sensors 2>/dev/null | grep -E 'Tctl:|Package id 0:|Core 0:' | head -1 | grep -oP '\+\K[0-9.]+' | head -1)

if [ -z "$temp" ]; then
    # Fallback to thermal zone
    temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{printf "%.0f", $1/1000}')
fi

if [ -z "$temp" ]; then
    temp="N/A"
fi

printf '{"text":"%s", "tooltip":"CPU: %s%%\\nTemp: %s°C"}' "$cpu" "$cpu" "$temp"
