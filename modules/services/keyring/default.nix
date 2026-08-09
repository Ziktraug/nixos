{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.services.keyring;
in
{
  options.applications.services.keyring = {
    enable = mkEnableOption "GNOME Keyring for password/session management";
  };

  config = mkIf cfg.enable {
    # Enable gnome-keyring service - handles daemon startup automatically
    services.gnome.gnome-keyring.enable = true;

    # Install required packages
    environment.systemPackages = with pkgs; [
      gnome-keyring
      libsecret # For secret-tool CLI and browser integration
      seahorse # GUI for managing keyring (optional)
    ];

    # Enable PAM integration for automatic keyring unlock on login
    # This unlocks the keyring using your login password automatically
    security.pam.services.greetd.enableGnomeKeyring = true;
    security.pam.services.gdm-password.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;
  };
}
