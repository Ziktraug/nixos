{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.ide.zed;
  release = builtins.fromJSON (builtins.readFile ./release.json);

  asset =
    if pkgs.stdenvNoCC.hostPlatform.system == "x86_64-linux" then
      release.assets.x86_64-linux
    else if pkgs.stdenvNoCC.hostPlatform.system == "aarch64-linux" then
      release.assets.aarch64-linux
    else
      throw "applications.devtools.ide.zed: unsupported system ${pkgs.stdenvNoCC.hostPlatform.system}";

  runtimeLibraryPath = lib.makeLibraryPath (
    with pkgs;
    [
      alsa-lib
      libGL
      stdenv.cc.cc.lib
      vulkan-loader
      wayland
    ]
  );

  zedPrebuilt = pkgs.stdenvNoCC.mkDerivation {
    pname = "zed-editor-bin";
    version = release.version;

    src = pkgs.fetchzip {
      url = "https://github.com/zed-industries/zed/releases/download/${release.tag}/${asset.file}";
      hash = asset.hash;
      stripRoot = false;
    };

    nativeBuildInputs = with pkgs; [
      makeWrapper
      patchelf
    ];

    dontConfigure = true;
    dontBuild = true;
    dontPatchELF = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      cp -a "$src/zed.app/." "$out/"
      chmod -R u+w "$out"

      for binary in "$out/bin/zed" "$out/libexec/zed-editor"; do
        if [ -x "$binary" ]; then
          patchelf \
            --set-interpreter '${pkgs.stdenv.cc.bintools.dynamicLinker}' \
            --set-rpath '$ORIGIN/../lib:${runtimeLibraryPath}:/run/opengl-driver/lib' \
            "$binary"
        fi
      done

      for library in "$out"/lib/*.so*; do
        if patchelf --print-rpath "$library" >/dev/null 2>&1; then
          patchelf \
            --set-rpath '$ORIGIN:${runtimeLibraryPath}:/run/opengl-driver/lib' \
            "$library"
        fi
      done

      ln -s "$out/bin/zed" "$out/bin/zeditor"

      runHook postInstall
    '';

    postFixup = ''
      wrapProgram "$out/bin/zed" \
        --set XKB_CONFIG_ROOT '${pkgs.xkeyboard_config}/share/X11/xkb' \
        --suffix LD_LIBRARY_PATH : '$out/lib:${runtimeLibraryPath}:/run/opengl-driver/lib'
    '';

    meta = {
      description = "High-performance, multiplayer code editor from the creators of Atom and Tree-sitter";
      homepage = "https://zed.dev";
      changelog = "https://github.com/zed-industries/zed/releases/tag/${release.tag}";
      license = lib.licenses.gpl3Only;
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      mainProgram = "zed";
    };
  };

  zedPackage = if cfg.package == "prebuilt" then zedPrebuilt else pkgs.zed-editor-fhs;
  zedWithCommand = pkgs.symlinkJoin {
    name = "zed-with-command-${zedPackage.version}";
    paths = [ zedPackage ];
    postBuild = ''
      test -x "$out/bin/zeditor"
      if [ ! -e "$out/bin/zed" ]; then
        ln -s zeditor "$out/bin/zed"
      fi
      test -x "$out/bin/zed"
    '';
    meta = zedPackage.meta // {
      mainProgram = "zed";
    };
  };
in
{
  options.applications.devtools.ide.zed = {
    enable = mkEnableOption "Zed editor";

    package = mkOption {
      type = types.enum [
        "prebuilt"
        "nixpkgs"
      ];
      default = "prebuilt";
      description = "Zed package source to install.";
    };

    keymapLayout = mkOption {
      type = types.enum [
        "fr"
        "us"
      ];
      default = "fr";
      description = "Keyboard layout variant used for layout-sensitive Zed keybindings.";
    };

    dotfiles = {
      enable = mkOption {
        type = types.bool;
        default = cfg.enable;
        description = "Manage Zed dotfiles";
      };
    };
  };

  config = mkIf cfg.enable {
    # Keep both upstream's `zeditor` entry point and the conventional `zed`
    # command in one profile package, so the two names cannot collide.
    environment.systemPackages = [ zedWithCommand ];

    dotfiles = mkIf cfg.dotfiles.enable {
      enable = true;
      modules.zed = {
        enable = true;
        sourceDir = "modules/devtools/ide/zed";
        mappings = {
          settings = {
            source = "settings.json";
            target = "$HOME/.config/zed/settings.json";
          };
          keymap = {
            source = "keymap.${cfg.keymapLayout}.json";
            target = "$HOME/.config/zed/keymap.json";
          };
        };
      };
    };
  };
}
