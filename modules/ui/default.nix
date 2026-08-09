{ ... }:

{
  imports = [
    # Desktop Environments
    ./gnome
    ./kde
    ./hyprland

    # Hyprland ecosystem (only active when hyprland enabled)
    ./waybar
    ./rofi-wayland
    ./rofi-networkmanager
    ./mako
    ./hyprpaper
    ./hypridle
    ./hyprlock
  ];
}
