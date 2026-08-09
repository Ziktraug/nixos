{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.shells.direnv;
in
{
  options.applications.devtools.shells.direnv = {
    enable = mkEnableOption "direnv shell environment loader";
  };

  config = mkIf cfg.enable {
    # Install direnv and nix-direnv
    environment.systemPackages = with pkgs; [
      direnv
      nix-direnv
    ];

    # Silence noisy direnv export logs
    environment.sessionVariables = {
      DIRENV_LOG_FORMAT = "";
    };

    # Enable direnv globally
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Ensure fish can find direnv completions and functions
    environment.pathsToLink = [ "/share/fish" ];

    # Add direnv hook to fish shell if fish is enabled
    programs.fish = mkIf config.applications.devtools.shells.fish.enable {
      interactiveShellInit = ''
        # Direnv hook for automatic environment loading
        direnv hook fish | source
      '';
    };
  };
}
