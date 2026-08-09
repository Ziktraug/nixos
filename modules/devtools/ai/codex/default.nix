{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ai.codex;
  release = builtins.fromJSON (builtins.readFile ./release.json);

  asset =
    if pkgs.stdenvNoCC.hostPlatform.system == "x86_64-linux" then
      release.assets.x86_64-linux
    else if pkgs.stdenvNoCC.hostPlatform.system == "aarch64-linux" then
      release.assets.aarch64-linux
    else
      throw "applications.devtools.ai.codex: unsupported system ${pkgs.stdenvNoCC.hostPlatform.system}";

  codex = pkgs.stdenvNoCC.mkDerivation {
    pname = "codex";
    version = release.version;

    srcs = [
      (pkgs.fetchurl {
        url = "https://github.com/openai/codex/releases/download/${release.tag}/${asset.file}";
        hash = asset.hash;
      })
      (pkgs.fetchurl {
        url = "https://github.com/openai/codex/releases/download/${release.tag}/${asset.codeModeHost.file}";
        hash = asset.codeModeHost.hash;
      })
    ];

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 ${asset.binary} "$out/bin/codex"
      install -Dm755 ${asset.codeModeHost.binary} "$out/bin/codex-code-mode-host"

      runHook postInstall
    '';

    meta = {
      description = "OpenAI coding agent that runs in the terminal";
      homepage = "https://github.com/openai/codex";
      changelog = "https://github.com/openai/codex/releases/tag/${release.tag}";
      license = lib.licenses.asl20;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mainProgram = "codex";
    };
  };
in
{
  options.applications.devtools.ai.codex = {
    enable = mkEnableOption "OpenAI Codex CLI";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.bubblewrap
      codex
    ];
  };
}
