{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
}:

let
  release = builtins.fromJSON (builtins.readFile ./release-v2.json);
in
stdenvNoCC.mkDerivation {
  pname = "opencode2";
  inherit (release) version;

  src = fetchurl {
    inherit (release) url hash;
  };

  sourceRoot = "package";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall

    install -Dm755 bin/opencode2 "$out/bin/opencode2"

    runHook postInstall
  '';

  meta = {
    description = "OpenCode 2 preview command-line coding agent";
    homepage = "https://opencode.ai/v2/docs";
    license = lib.licenses.mit;
    mainProgram = "opencode2";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
