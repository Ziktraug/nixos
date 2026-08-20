{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai.opencode;
  dotfilesUser = config.dotfiles.user;
  userHome = config.users.users.${dotfilesUser}.home;
  opencode2Raw = pkgs.callPackage ./package-v2.nix { };
  opencode2 = pkgs.symlinkJoin {
    name = "opencode2-${opencode2Raw.version}";
    paths = [ opencode2Raw ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/opencode2" \
        --set OPENCODE_CONFIG_DIR ${escapeShellArg "${userHome}/.config/opencode2/opencode"} \
        --set OPENCODE_DISABLE_AUTOUPDATE true
    '';
    meta = opencode2Raw.meta;
  };
  desktopExec = "OpenCode";
  opencodeDesktopEntry = pkgs.writeTextFile {
    name = "opencode-kde-desktop-entry";
    destination = "/share/applications/opencode-ai.desktop";
    text = ''
      [Desktop Entry]
      Version=1.5
      Type=Application
      Name=OpenCode
      GenericName=AI Coding Agent
      Comment=AI coding agent desktop client
      Exec=${desktopExec}
      Icon=OpenCode
      Terminal=false
      StartupWMClass=OpenCode
      Categories=Development;IDE;
      Keywords=AI;Coding;Assistant;
      MimeType=x-scheme-handler/opencode;
    '';
  };
in
{
  options.applications.devtools.ai.opencode = {
    enable = mkEnableOption "OpenCode AI coding agent";

    web = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Start opencode web UI as a user service on login";
      };
      port = mkOption {
        type = types.int;
        default = 4096;
        description = "Port for the opencode web UI";
      };
    };

    desktop = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Install the OpenCode desktop application";
      };
    };

    v2 = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Install the OpenCode 2 preview alongside OpenCode 1";
      };
      web = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Start the isolated OpenCode 2 preview web service on login";
        };
        port = mkOption {
          type = types.port;
          default = 4097;
          description = "Port for the OpenCode 2 preview web service";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    applications.devtools.cli.rtk.enable = mkDefault true;

    environment.systemPackages =
      with pkgs;
      [
        opencode
      ]
      ++ optional cfg.v2.enable opencode2
      ++ optionals cfg.desktop.enable [
        opencode-desktop
        opencodeDesktopEntry
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
      ];

    systemd.user.services.opencode-web = mkIf cfg.web.enable {
      description = "OpenCode web UI";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      environment = {
        PATH = mkForce (
          concatStringsSep ":" [
            "/run/wrappers/bin"
            "%h/.nix-profile/bin"
            "/nix/profile/bin"
            "%h/.local/state/nix/profile/bin"
            "/etc/profiles/per-user/${config.dotfiles.user}/bin"
            "/nix/var/nix/profiles/default/bin"
            "/run/current-system/sw/bin"
          ]
        );
      };
      serviceConfig = {
        ExecStart = "${pkgs.opencode}/bin/opencode web --port ${toString cfg.web.port}";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    systemd.user.services.opencode2-web = mkIf (cfg.v2.enable && cfg.v2.web.enable) {
      description = "OpenCode 2 preview web UI";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${opencode2}/bin/opencode2 serve --hostname 127.0.0.1 --port ${toString cfg.v2.web.port}";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };

    dotfiles.modules.opencode = {
      enable = true;
      sourceDir = "modules/devtools/ai/opencode";
      mappings = {
        config = {
          source = "opencode.json";
          target = "$HOME/.config/opencode/opencode.json";
        };
        plugin-openrtk = {
          source = "plugins/openrtk.ts";
          target = "$HOME/.config/opencode/plugins/openrtk.ts";
        };
        rtk-instructions = {
          source = "RTK.md";
          target = "$HOME/.config/opencode/RTK.md";
        };
        agent-memory-instructions = {
          source = "AGENT_MEMORY.md";
          target = "$HOME/.config/opencode/AGENT_MEMORY.md";
        };
        setup-agent-memory-skill = {
          source = "skills/setup-agent-memory/SKILL.md";
          target = "$HOME/.config/opencode/skills/setup-agent-memory/SKILL.md";
        };
      }
      // optionalAttrs cfg.v2.enable {
        v2-config = {
          source = "v2/opencode.json";
          target = "$HOME/.config/opencode2/opencode/opencode.json";
        };
        v2-instructions = {
          source = "v2/AGENTS.md";
          target = "$HOME/.config/opencode2/opencode/AGENTS.md";
        };
        v2-plugin-openrtk = {
          source = "v2/plugins/openrtk.ts";
          target = "$HOME/.config/opencode2/opencode/v2/plugins/openrtk.ts";
        };
        v2-plugin-secure-agents = {
          source = "v2/plugins/secure-agents.ts";
          target = "$HOME/.config/opencode2/opencode/v2/plugins/secure-agents.ts";
        };
        v2-setup-agent-memory-skill = {
          source = "skills/setup-agent-memory/SKILL.md";
          target = "$HOME/.config/opencode2/opencode/skills/setup-agent-memory/SKILL.md";
        };
      };
    };
  };
}
