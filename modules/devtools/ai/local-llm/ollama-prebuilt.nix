{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
  patchelf,
  stdenv,
  zstd,
}:

let
  release = builtins.fromJSON (builtins.readFile ./release.json);

  asset =
    if stdenvNoCC.hostPlatform.system == "x86_64-linux" then
      release.assets.x86_64-linux
    else
      throw "applications.devtools.ai.\"local-llm\": unsupported system ${stdenvNoCC.hostPlatform.system}";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ollama";
  version = release.version;

  src = fetchzip {
    url = "https://github.com/ollama/ollama/releases/download/${release.tag}/${asset.file}";
    curlOptsList = [ "--http1.1" ];
    hash = asset.hash;
    extension = "tar.zst";
    stripRoot = false;
    nativeBuildInputs = [ zstd ];
  };

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    if [ -d "$src/usr" ]; then
      cp -a "$src/usr/." "$out/"
    else
      cp -a "$src/." "$out/"
    fi

    chmod -R u+w "$out"

    if [ ! -x "$out/bin/ollama" ]; then
      echo "Expected prebuilt Ollama binary at $out/bin/ollama" >&2
      exit 1
    fi

    patchelf \
      --set-interpreter '${stdenv.cc.bintools.dynamicLinker}' \
      --set-rpath '${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}' \
      "$out/bin/ollama"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/ollama" \
      --suffix LD_LIBRARY_PATH : '$out/lib/ollama:$out/lib/ollama/cuda_v12:$out/lib/ollama/cuda_v13:$out/lib/ollama/mlx_cuda_v13:${
        lib.makeLibraryPath [ stdenv.cc.cc.lib ]
      }:/run/opengl-driver/lib'
  '';

  meta = {
    description = "Prebuilt upstream Ollama package for Linux amd64";
    homepage = "https://ollama.com";
    changelog = "https://github.com/ollama/ollama/releases/tag/${release.tag}";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ollama";
  };
})
