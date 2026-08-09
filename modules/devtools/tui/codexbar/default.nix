{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.tui.codexbar;

  codexbarCli = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "codexbar-cli";
    version = "0.18.0-beta.3";

    src = pkgs.fetchurl {
      url = "https://github.com/steipete/CodexBar/releases/download/v${version}/CodexBarCLI-v${version}-linux-x86_64.tar.gz";
      sha256 = "add75cf9f85f975d059f1f6278779dbbb003a7a671c14b345b4e5a8f87dc3e40";
    };

    sourceRoot = ".";

    nativeBuildInputs = [ pkgs.autoPatchelfHook ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.libxml2_13.out
      pkgs.sqlite
      pkgs.curl
      pkgs.openssl
      pkgs.zlib
      pkgs.zstd
      pkgs.libidn2
      pkgs.libssh2
      pkgs.libpsl
      pkgs.nghttp2
      pkgs.nghttp3
      pkgs.ngtcp2
      pkgs.krb5
      pkgs.brotli
      pkgs.keyutils
      pkgs.libunistring
    ];

    installPhase = ''
      runHook preInstall

      install -Dm755 CodexBarCLI "$out/bin/CodexBarCLI"
      install -Dm755 codexbar "$out/bin/codexbar"

      runHook postInstall
    '';

    meta = with lib; {
      description = "CLI usage tracker for AI coding subscriptions";
      homepage = "https://github.com/steipete/CodexBar";
      license = licenses.mit;
      platforms = [ "x86_64-linux" ];
      mainProgram = "codexbar";
    };
  };
in
{
  options.applications.devtools.tui.codexbar = {
    enable = mkEnableOption "CodexBar CLI for AI usage tracking";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ codexbarCli ];
  };
}
