{ ... }:

{
  applications = {
    browsers = {
      brave.enable = true;
      firefox.enable = true;
      zen-browser = {
        enable = true;
        dotfiles.enable = true;
      };
    };

    design.figma.enable = true;
    file-managers.nautilus.enable = true;

    devtools = {
      git.enable = true;
      nix-ld.enable = true;
      nix-dev.enable = true;
      package-version-server.enable = true;

      cli = {
        github.enable = true;
        rtk.enable = true;
      };

      ide = {
        cursor.enable = true;
        vscode.enable = true;
        zed.enable = true;
      };

      shells = {
        fish.enable = true;
        direnv.enable = true;
        aliases.enable = true;
      };

      terminals.ghostty.enable = true;

      ai = {
        opencode.enable = true;
        claude-code.enable = true;
        codex.enable = true;
        "global-skills".enable = true;
        agent-memory = {
          enable = true;
          globalRepoPath = "/srv/alice/agent-memory";
          managedRepos = [ "/srv/alice/nixos" ];
        };
      };

      tui = {
        codex-monitor.enable = true;
        ocmonitor.enable = true;
        update-tui.enable = true;
      };

      browser-automation.enable = true;
    };

    games = {
      steam.enable = true;
      gamemode.enable = true;
      heroic.enable = true;
      mangohud.enable = true;
    };

    hardware = {
      solaar.enable = false;
      logitechHeadsetBattery.enable = false;
    };

    media.vlc.enable = true;
    services.keyring.enable = true;

    system = {
      btop.enable = true;
      mission-center.enable = true;
    };

    ui.gnome.enable = true;
  };
}
