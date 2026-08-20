{
  lib,
  stdenv,
  fetchurl,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  coreutils,
  cups,
  dbus,
  dpkg,
  expat,
  fontconfig,
  freetype,
  gdk-pixbuf,
  glib,
  gsettings-desktop-schemas,
  graphite2,
  gtk3,
  harfbuzz,
  libappindicator-gtk3,
  libdrm,
  libgbm,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libusb1,
  libx11,
  libxcb,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxkbcommon,
  libxrandr,
  libxrender,
  libxscrnsaver,
  libxshmfence,
  libxtst,
  makeWrapper,
  nspr,
  nss,
  openssl,
  pango,
  qt5,
  qt6,
  systemdLibs,
  wayland,
  wrapGAppsHook3,
  xdg-utils,
  zlib,
}:

let
  release = builtins.fromJSON (builtins.readFile ./release.json);

  runtimeLibraries = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    fontconfig
    freetype
    gdk-pixbuf
    glib
    graphite2
    gtk3
    harfbuzz
    libappindicator-gtk3
    libdrm
    libgbm
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    libusb1
    libx11
    libxcb
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxkbcommon
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    nspr
    openssl
    pango
    stdenv.cc.cc
    systemdLibs
    wayland
    zlib
  ];

  qtLibraries = [
    qt5.qtbase
    qt6.qtbase
  ];
in
stdenv.mkDerivation {
  pname = "chatgpt-desktop";
  inherit (release) version;

  src = fetchurl {
    inherit (release) url hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
    wrapGAppsHook3
  ];

  buildInputs = runtimeLibraries ++ [
    gsettings-desktop-schemas
    nss
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontUnpack = true;
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    dpkg-deb -x "$src" "$out"

    mkdir -p "$out/bin" "$out/lib" "$out/share/applications" "$out/share/pixmaps"
    mv "$out/usr/lib/chatgpt" "$out/lib/chatgpt"
    mv "$out/usr/share/applications/chatgpt.desktop" "$out/share/applications/chatgpt.desktop"
    mv "$out/usr/share/pixmaps/chatgpt.png" "$out/share/pixmaps/chatgpt.png"

    substituteInPlace "$out/lib/chatgpt/codex-launcher" \
      --replace-fail 'dirname' '${coreutils}/bin/dirname' \
      --replace-fail 'readlink -f' '${coreutils}/bin/readlink -f'
    ln -s ../lib/chatgpt/codex-launcher "$out/bin/chatgpt"

    find "$out/lib/chatgpt" -type d \
      \( \
        -name 'android-*' \
        -o -name 'darwin-*' \
        -o -name 'win32-*' \
        -o -name 'linux-arm' \
        -o -name 'linux-arm64' \
        -o -name '*musl*' \
      \) \
      -prune -exec rm -rf {} +
    find "$out/lib/chatgpt" -type f -name '*musl*' -delete

    rm -rf "$out/usr" "$out/etc"

    addAutoPatchelfSearchPath "$out/lib/chatgpt"
    addAutoPatchelfSearchPath "${qt5.qtbase}/lib"
    addAutoPatchelfSearchPath "${qt6.qtbase}/lib"

    runHook postInstall
  '';

  autoPatchelfIgnoreMissingDeps = [
    "libc++_shared.so"
    "libc.musl-x86_64.so.1"
    "liblog.so"
  ];

  postFixup = ''
    wrapProgram "$out/lib/chatgpt/ChatGPT" \
      "''${gappsWrapperArgs[@]}" \
      --prefix PATH : ${
        lib.makeBinPath [
          glib
          xdg-utils
        ]
      } \
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath (runtimeLibraries ++ qtLibraries)
      }:$out/lib/chatgpt \
      --add-flags "--disable-gpu --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true"
  '';

  meta = {
    description = "ChatGPT desktop application by OpenAI";
    homepage = "https://learn.chatgpt.com/docs/app";
    license = lib.licenses.unfree;
    mainProgram = "chatgpt";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
