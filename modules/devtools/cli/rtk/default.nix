{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.cli.rtk;

  release = builtins.fromJSON (builtins.readFile ./release.json);

  asset =
    if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
      release.assets.x86_64-linux
    else if pkgs.stdenv.hostPlatform.system == "aarch64-linux" then
      release.assets.aarch64-linux
    else
      throw "applications.devtools.cli.rtk: unsupported system ${pkgs.stdenv.hostPlatform.system}";

  rtk = pkgs.stdenvNoCC.mkDerivation {
    pname = "rtk";
    version = release.version;

    src = pkgs.fetchurl {
      url = "https://github.com/rtk-ai/rtk/releases/download/${release.tag}/${asset.file}";
      sha256 = asset.sha256;
    };

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      if [ -f rtk ]; then
        install -Dm755 rtk "$out/bin/rtk"
      else
        rtk_bin="$(find . -type f -name rtk | head -n1)"
        if [ -z "$rtk_bin" ]; then
          echo "Could not find rtk binary in release archive" >&2
          exit 1
        fi
        install -Dm755 "$rtk_bin" "$out/bin/rtk"
      fi

      runHook postInstall
    '';

    meta = with lib; {
      description = "Rust Token Killer - token-optimized CLI proxy";
      homepage = "https://github.com/rtk-ai/rtk";
      license = licenses.mit;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mainProgram = "rtk";
    };
  };
in
{
  options.applications.devtools.cli.rtk = {
    enable = mkEnableOption "RTK (Rust Token Killer)";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ rtk ];
  };
}
