{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.kde;
in
{
  options.applications.ui.kde = {
    enable = mkEnableOption "KDE Plasma 6 desktop environment";

    autoNumlock = mkOption {
      type = types.bool;
      default = true;
      description = "Enable numlock on startup";
    };

    dotfiles.enable = mkEnableOption "KDE dotfiles management (power settings, etc.)";
  };

  config = mkIf cfg.enable {
    # Assertions
    assertions = [
      {
        assertion = !config.applications.ui.hyprland.enable;
        message = "Cannot enable both KDE and Hyprland. Disable Hyprland in modules.nix";
      }
      {
        assertion = !config.services.greetd.enable;
        message = "KDE requires SDDM. greetd is still enabled - check for conflicts";
      }
    ];

    # SDDM Display Manager
    # NOTE: Plasma 6 defaults to Wayland SDDM (PR #368074), but this causes
    # KWallet timing issues with NetworkManager at boot (KDE Bug #400928).
    # Explicitly disable Wayland for SDDM to use X11 mode.
    services.displayManager.sddm = {
      enable = true;
      autoNumlock = cfg.autoNumlock;
      wayland.enable = false; # Force X11 - fixes KWallet race condition

      # Fix greeter Qt platform plugin mismatch (greeter was trying to use Wayland even with X11)
      settings.General.GreeterEnvironment = "QT_QPA_PLATFORM=xcb";
    };

    # KDE Plasma 6 Desktop
    services.desktopManager.plasma6.enable = true;

    # KWallet for password/secrets management (integrates with browsers)
    # This replaces gnome-keyring when using KDE
    security.pam.services.sddm.enableKwallet = true;
    security.pam.services.login.enableKwallet = true;

    # Ensure X server is enabled (required for SDDM)
    services.xserver.enable = true;

    # Input device support (CRITICAL for keyboard/mouse at SDDM)
    services.libinput.enable = true;

    # Additional services for KDE
    services.udisks2.enable = true; # Auto-mounting
    services.gvfs.enable = true; # Trash and other features
    security.polkit.enable = true; # PolicyKit for privileged operations

    # XDG Portal for KDE (screen sharing, file dialogs, etc.)
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.kdePackages.xdg-desktop-portal-kde ];
      # Explicitly set KDE as the preferred portal implementation
      config.common.default = "kde";
    };

    # Environment variables for KDE
    environment.sessionVariables = {
      XDG_CURRENT_DESKTOP = "KDE";
      QT_QPA_PLATFORM = "wayland";
      KDE_SESSION_VERSION = "6";

      # NVIDIA environment variables for hardware acceleration
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };

    # Ensure KDE session components are available
    environment.systemPackages = with pkgs; [
      kdePackages.kwin # Window manager
      kdePackages.krunner # Application launcher
      kdePackages.plasma-workspace # Plasma workspace components (includes panel)
      kdePackages.plasma-desktop # Desktop shell
      kdePackages.systemsettings # System settings
      kdePackages.konsole # Terminal
      kdePackages.dolphin # File manager
      kdePackages.kmenuedit # Menu editor

      # KWallet integration for browser session persistence
      kdePackages.kwallet-pam # PAM module for KWallet auto-unlock
      libsecret # Secret Service API for browser integration (critical for Zen/Firefox)
    ];

    # Dotfiles management for KDE settings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.kde = {
        enable = true;
        sourceDir = "modules/ui/kde";
        mappings = {
          powerdevil = {
            source = "config/powerdevilrc";
            target = "$HOME/.config/powerdevilrc";
          };
        };
      };
    };
  };
}
