{
  config,
  lib,
  pkgs,
  zen-browser,
  ...
}:

let
  cfg = config.applications.browsers.zen-browser;
  userHome = config.users.users.${config.dotfiles.user}.home;
  zenProfileSyncScript = pkgs.writeShellScript "sync-zen-browser-profile" ''
    set -euo pipefail
    export HOME=${lib.escapeShellArg userHome}
    export NIXOS_REPO=${lib.escapeShellArg config.dotfiles.repoPath}
    export PATH=${
      lib.escapeShellArg (
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.diffutils
          pkgs.findutils
          pkgs.gawk
        ]
      )
    }
    exec ${pkgs.bash}/bin/bash ${./setup-zen-config.sh}
  '';
in
{
  options.applications.browsers.zen-browser = {
    enable = lib.mkEnableOption "Zen browser";
    dotfiles.enable = lib.mkEnableOption "Zen browser dotfiles management";
  };

  config = lib.mkIf cfg.enable {
    # Install Zen browser
    environment.systemPackages = [
      zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    # Dotfiles management (placeholder for future configuration)
    dotfiles = lib.mkIf cfg.dotfiles.enable {
      enable = true;
      modules.zen-browser = {
        enable = true;
        sourceDir = "modules/browsers/zen-browser";
        mappings = {
          userjs = {
            source = "user.js";
            target = "$HOME/.config/.mozilla/zen/user.js";
          };
          setupScript = {
            source = "setup-zen-config.sh";
            executable = true;
            target = "$HOME/.local/bin/setup-zen-config";
          };
          userChrome = {
            source = "chrome/userChrome.css";
            target = "$HOME/.config/.mozilla/zen/chrome/userChrome.css";
          };
          userContent = {
            source = "chrome/userContent.css";
            target = "$HOME/.config/.mozilla/zen/chrome/userContent.css";
          };
        };
      };
    };

    systemd.user.services.zen-browser-profile-sync = lib.mkIf cfg.dotfiles.enable {
      description = "Sync managed configuration into the active Zen profile";
      requires = [ "dotfiles-manager.service" ];
      after = [ "dotfiles-manager.service" ];
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = zenProfileSyncScript;
      };
    };
  };
}
