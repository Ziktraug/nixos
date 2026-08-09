{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.hyprland;
in
{
  options.applications.ui.hyprland = {
    enable = mkEnableOption "Hyprland wayland compositor";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Hyprland dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    # Enable Hyprland
    programs.hyprland = {
      enable = true;
      xwayland.enable = true;
    };

    # Install additional packages for complete desktop experience
    environment.systemPackages = with pkgs; [
      grim # Screenshot utility
      slurp # Screen area selection
      wl-clipboard # Wayland clipboard utilities
      pavucontrol # Audio control
      brightnessctl # Brightness control
      bibata-cursors # Cursor theme
      dex # XDG autostart executor
    ];

    # Minimal NVIDIA environment variables for Hyprland
    environment.sessionVariables = {
      # Essential NVIDIA variables only
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      WLR_NO_HARDWARE_CURSORS = "1";

      # Cursor theme
      XCURSOR_THEME = "Bibata-Modern-Classic";
      XCURSOR_SIZE = "24";

      # XDG Desktop Portal - required for Secret Service and file dialogs
      XDG_CURRENT_DESKTOP = "Hyprland";
    };

    # Enable required services
    security.polkit.enable = true;

    # Enable display manager for Hyprland
    services.greetd = {
      enable = true;
      settings = mkMerge [
        # Default greetd session (when auto-login is disabled)
        (mkIf (!config.services.displayManager.autoLogin.enable) {
          default_session = {
            command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
            user = "greeter";
          };
        })
        # Auto-login session (when auto-login is enabled)
        (mkIf config.services.displayManager.autoLogin.enable {
          default_session = {
            command = "${pkgs.hyprland}/bin/start-hyprland";
            user = config.services.displayManager.autoLogin.user;
          };
        })
      ];
    };

    # Enable additional services
    services.udisks2.enable = true; # Auto-mounting
    services.gvfs.enable = true; # Trash and other features

    # Enable XDG portal for screen sharing
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    # Configure dotfiles with inline mappings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.hyprland = {
        enable = true;
        sourceDir = "modules/ui/hyprland";
        mappings = {
          hyprland = {
            source = "hyprland.conf";
            target = "$HOME/.config/hypr/hyprland.conf";
          };
          gaming-mode-script = {
            source = "scripts/toggle-gaming-mode.sh";
            target = "$HOME/.config/hypr/scripts/toggle-gaming-mode.sh";
          };
          gtk3-settings = {
            source = "gtk-3.0-settings.ini";
            target = "$HOME/.config/gtk-3.0/settings.ini";
          };
          gtk4-settings = {
            source = "gtk-3.0-settings.ini";
            target = "$HOME/.config/gtk-4.0/settings.ini";
          };
        };
      };
    };
  };
}
