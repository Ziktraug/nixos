#!/usr/bin/env bash
# Gaming Mode Toggle for Hyprland
# Disables secondary monitors to prevent cursor from escaping during gaming
# See: https://github.com/hyprwm/Hyprland/issues/2376

STATE_FILE="/tmp/hyprland-gaming-mode"

# Monitor configuration (from hyprland.conf)
# Left monitor (vertical): HDMI-A-2
# Center monitor (4K primary): DP-3
# Right monitor: HDMI-A-1

enable_gaming_mode() {
    # Disable side monitors
    hyprctl keyword monitor "HDMI-A-2, disable"
    hyprctl keyword monitor "HDMI-A-1, disable"
    touch "$STATE_FILE"
    notify-send "Gaming Mode" "Enabled - Side monitors disabled" -t 2000
}

disable_gaming_mode() {
    # Re-enable side monitors with original configuration
    hyprctl keyword monitor "HDMI-A-2, 1920x1080@60, 0x0, 1, transform, 1"
    hyprctl keyword monitor "HDMI-A-1, 1920x1080@60, 4920x540, 1"
    rm -f "$STATE_FILE"
    notify-send "Gaming Mode" "Disabled - Side monitors restored" -t 2000
}

# Toggle based on current state
if [ -f "$STATE_FILE" ]; then
    disable_gaming_mode
else
    enable_gaming_mode
fi
