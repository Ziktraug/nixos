#!/run/current-system/sw/bin/bash
# Solaar battery monitoring script for Waybar

tooltip=""
lowest_battery=100
device_count=0

# Parse solaar show output directly
while IFS= read -r line; do
    # Check if line contains battery percentage
    if [[ "$line" =~ Battery:.*([0-9]+)% ]]; then
        battery="${BASH_REMATCH[1]}"
        if [[ "$battery" =~ ^[0-9]+$ ]] && [ "$battery" -lt "$lowest_battery" ]; then
            lowest_battery="$battery"
        fi
    fi
    # Check for device name lines (start with number:)
    if [[ "$line" =~ ^[[:space:]]*([0-9]+):[[:space:]]*(.+)$ ]]; then
        current_device="${BASH_REMATCH[2]}"
    fi
    # When we find a battery line, record the device
    if [[ "$line" =~ Battery:.*([0-9]+)% ]] && [ -n "$current_device" ]; then
        battery="${BASH_REMATCH[1]}"
        device_count=$((device_count + 1))
        if [ -n "$tooltip" ]; then
            tooltip="${tooltip}\\n"
        fi
        tooltip="${tooltip}${current_device}: ${battery}%"
        current_device=""
    fi
done < <(solaar show 2>/dev/null; for i in 1 2 3 4; do solaar show "$i" 2>/dev/null; done)

if [ "$device_count" -eq 0 ]; then
    printf '{"text":"N/A", "tooltip":"No Logitech devices"}'
else
    printf '{"text":"%s", "tooltip":"%s"}' "$lowest_battery" "$tooltip"
fi
