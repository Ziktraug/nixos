{
  config,
  pkgs,
  lib,
  ocmonitor,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.tui.ocmonitor;
  dotfilesUser = config.dotfiles.user;
  userHome = config.users.users.${dotfilesUser}.home;

  ocmonitorPkg = pkgs.python3Packages.buildPythonApplication rec {
    pname = "ocmonitor";
    version = "unstable-${builtins.substring 0 10 ocmonitor.lastModifiedDate or "19700101"}";

    src = ocmonitor;

    pyproject = true;

    build-system = with pkgs.python3Packages; [
      setuptools
      wheel
    ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      click
      rich
      pydantic
      prometheus-client
      pyyaml
      toml
      pandas
      matplotlib
    ];

    meta = with lib; {
      description = "CLI tool for monitoring and analyzing OpenCode AI coding usage";
      homepage = "https://github.com/Shlomob/ocmonitor-share";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "ocmonitor";
    };
  };
in
{
  options.applications.devtools.tui.ocmonitor = {
    enable = mkEnableOption "OpenCode Monitor - CLI tool for monitoring OpenCode AI usage";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ ocmonitorPkg ];

    # Create ocmonitor config directory
    dotfiles.modules.ocmonitor = {
      enable = true;
      sourceDir = "modules/devtools/tui/ocmonitor";
      mappings = {
        config = {
          source = "config.toml";
          target = "$HOME/.config/ocmonitor/config.toml";
        };
      };
    };

    systemd.user.services.ocmonitor-directories = {
      description = "Create ocmonitor user directories";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "create-ocmonitor-directories" ''
          set -euo pipefail
          test "$(${pkgs.coreutils}/bin/id -un)" = ${lib.escapeShellArg dotfilesUser}
          ${pkgs.coreutils}/bin/mkdir -p \
            ${lib.escapeShellArg "${userHome}/.config/ocmonitor"} \
            ${lib.escapeShellArg "${userHome}/.local/share/ocmonitor/exports"}
        '';
        Environment = "HOME=${userHome}";
      };
    };
  };
}
