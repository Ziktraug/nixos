{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.ui.gnome;
  protonvpnEnabled = config.applications.services.networking.protonvpn.enable;
  appIndicatorUuid = "appindicatorsupport@rgcjonas.gmail.com";
  logitechBatteryUuid = "logitech-battery@example.com";
  enabledExtensions = [ logitechBatteryUuid ] ++ optionals protonvpnEnabled [ appIndicatorUuid ];
  logitechBatteryExtension = pkgs.stdenvNoCC.mkDerivation {
    pname = "gnome-shell-extension-logitech-battery";
    version = "1.0.0";
    src = ./logitech-battery-extension;

    installPhase = ''
      runHook preInstall

      extension_dir="$out/share/gnome-shell/extensions/${logitechBatteryUuid}"
      mkdir -p "$extension_dir"
      cp extension.js metadata.json "$extension_dir/"

      runHook postInstall
    '';
  };
in
{
  options.applications.ui.gnome = {
    enable = mkEnableOption "GNOME desktop environment";

    extras = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Install a small set of GNOME power-user utilities";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.applications.ui.kde.enable;
        message = "Cannot enable both GNOME and KDE. Disable KDE in modules.nix";
      }
      {
        assertion = !config.applications.ui.hyprland.enable;
        message = "Cannot enable both GNOME and Hyprland. Disable Hyprland in modules.nix";
      }
      {
        assertion = !config.services.greetd.enable;
        message = "GNOME uses GDM. greetd is still enabled - check for conflicts";
      }
    ];

    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    services.gnome = {
      core-apps.enable = false;
      core-developer-tools.enable = false;
      games.enable = false;
    };

    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      gnome-user-docs
    ];

    services.xserver.enable = true;
    services.libinput.enable = true;
    services.udisks2.enable = true;
    services.gvfs.enable = true;
    security.polkit.enable = true;

    programs.dconf.enable = true;

    programs.dconf.profiles.user.databases = [
      {
        settings = {
          "org/gnome/desktop/interface" = {
            color-scheme = "prefer-dark";
            cursor-size = lib.gvariant.mkInt32 24;
            cursor-theme = "Bibata-Modern-Classic";
            gtk-theme = "catppuccin-mocha-mauve-standard+default";
            icon-theme = "Papirus-Dark";
          };
          "org/gnome/mutter" = {
            experimental-features = [ "scale-monitor-framebuffer" ];
          };
          "org/gnome/desktop/wm/keybindings" = {
            switch-applications = [ "<Super>Tab" ];
            switch-applications-backward = [ "<Shift><Super>Tab" ];
            switch-windows = [ "<Alt>Tab" ];
            switch-windows-backward = [ "<Shift><Alt>Tab" ];
          };
          "org/gnome/shell" = {
            enabled-extensions = enabledExtensions;
          };
        };

        locks = [
          "/org/gnome/desktop/interface/color-scheme"
          "/org/gnome/desktop/interface/cursor-size"
          "/org/gnome/desktop/interface/cursor-theme"
          "/org/gnome/desktop/interface/gtk-theme"
          "/org/gnome/desktop/interface/icon-theme"
          "/org/gnome/desktop/wm/keybindings/switch-applications"
          "/org/gnome/desktop/wm/keybindings/switch-applications-backward"
          "/org/gnome/desktop/wm/keybindings/switch-windows"
          "/org/gnome/desktop/wm/keybindings/switch-windows-backward"
          "/org/gnome/mutter/experimental-features"
        ];
      }
    ];

    environment.sessionVariables = {
      XCURSOR_THEME = "Bibata-Modern-Classic";
      XCURSOR_SIZE = "24";
    };

    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
      config.common.default = "gnome";
    };

    environment.systemPackages =
      with pkgs;
      [
        loupe
        logitechBatteryExtension
      ]
      ++ optionals cfg.extras.enable [
        gnome-tweaks
        gnome-extension-manager
      ]
      ++ optionals protonvpnEnabled [
        gnomeExtensions.appindicator
      ];
  };
}
