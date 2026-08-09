{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.media.vlc;
  vlcOutputsToInstall = lib.unique (pkgs.vlc.meta.outputsToInstall or [ "out" ]);
  vlcWithDefaults = pkgs.symlinkJoin {
    name = "vlc-with-defaults-${pkgs.vlc.version}";
    outputs = vlcOutputsToInstall;
    paths = [ pkgs.vlc.out ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/vlc" --add-flags --no-qt-privacy-ask
    ''
    + lib.concatMapStringsSep "\n" (
      output:
      lib.optionalString (output != "out") ''
        outputPath="$(printenv ${lib.escapeShellArg output})"
        mkdir -p "$outputPath"
        ${pkgs.lndir}/bin/lndir -silent ${pkgs.vlc.${output}} "$outputPath"
      ''
    ) vlcOutputsToInstall;
    meta = pkgs.vlc.meta;
  };
in
{
  options.applications.media.vlc = {
    enable = mkEnableOption "VLC media player";

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Enable VLC dotfiles management";
      };
    };
  };

  config = mkIf cfg.enable {
    # Install the complete VLC output with a wrapped launcher, avoiding a
    # duplicate bin/vlc entry in the system profile.
    environment.systemPackages = [ vlcWithDefaults ];

    # Configure dotfiles with inline mappings
    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.vlc = {
        enable = true;
        sourceDir = "modules/media/vlc";
        mappings = {
          vlcrc = {
            source = "vlcrc";
            target = "$HOME/.config/vlc/vlcrc";
          };
        };
      };
    };
  };
}
