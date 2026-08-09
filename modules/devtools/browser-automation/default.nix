{
  config,
  pkgs,
  lib,
  ...
}:

with lib;

let
  cfg = config.applications.devtools.browser-automation;

  # Path to system Chrome
  chromePath = "${pkgs.google-chrome}/bin/google-chrome-stable";

  playwrightCliVersion = "0.1.17";
  playwrightVersion = "1.62.0-alpha-1783623505000";
  playwrightCliSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@playwright/cli/-/cli-${playwrightCliVersion}.tgz";
    hash = "sha512-VBw6y3p8eqOqmjKg07IkWSPGKJkpIhMRNDFI6DOYsDD6fAfcI1XYEWMLWyhSZQ0B/Oc2KN49eq4XqE64PUPHBg==";
  };
  playwrightSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/playwright/-/playwright-${playwrightVersion}.tgz";
    hash = "sha512-6KV9h4PP3hqu4NaGdxxcijWfYh9LJcFI/R2sP4TTC4I5cFo3oRawN0ETlW5MkE3cQEgKhhoj0KUNz4sfpCT0Tg==";
  };
  playwrightCoreSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/playwright-core/-/playwright-core-${playwrightVersion}.tgz";
    hash = "sha512-CPJZdsA/KGT2QQlekiV6Wt+QlQrZHVSZ6oiNtOI/bYYOIVLM8jfKGWTM4zQiyd4UN+40Cq4cA6lxmZHZbtPvJQ==";
  };

  playwright-cli-nixos =
    pkgs.runCommand "playwright-cli-${playwrightCliVersion}"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "playwright-cli";
      }
      ''
        mkdir -p \
          "$out/bin" \
          "$out/lib/node_modules/@playwright/cli" \
          "$out/lib/node_modules/playwright" \
          "$out/lib/node_modules/playwright-core"
        tar -xzf ${playwrightCliSource} --strip-components=1 -C "$out/lib/node_modules/@playwright/cli"
        tar -xzf ${playwrightSource} --strip-components=1 -C "$out/lib/node_modules/playwright"
        tar -xzf ${playwrightCoreSource} --strip-components=1 -C "$out/lib/node_modules/playwright-core"

        makeWrapper ${pkgs.nodejs}/bin/node "$out/bin/playwright-cli" \
          --add-flags "$out/lib/node_modules/@playwright/cli/playwright-cli.js" \
          --prefix NODE_PATH : "$out/lib/node_modules" \
          --set PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
          --set PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true \
          --set PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH ${lib.escapeShellArg chromePath} \
          --set PLAYWRIGHT_MCP_EXECUTABLE_PATH ${lib.escapeShellArg chromePath} \
          --set PLAYWRIGHT_MCP_BROWSER chrome \
          --set CHROME_BIN ${lib.escapeShellArg chromePath} \
          --set CHROME_PATH ${lib.escapeShellArg chromePath}
      '';

in
{
  options.applications.devtools.browser-automation = {
    enable = mkEnableOption "Browser automation support for AI coding tools (Playwright CLI)";
  };

  config = mkIf cfg.enable {
    # Ensure Chrome is available (unfree)
    unfreePackages = [ "google-chrome" ];

    # Install Chrome and Playwright CLI wrapper
    environment.systemPackages = with pkgs; [
      google-chrome
      playwright-cli-nixos
    ];

    # System-wide environment variables for browser automation
    environment.sessionVariables = {
      # Tell Playwright not to download its own browser
      PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
      PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";

      # Point to NixOS Chrome
      PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = chromePath;
      PLAYWRIGHT_MCP_EXECUTABLE_PATH = chromePath;
      PLAYWRIGHT_MCP_BROWSER = "chrome";

      # CHROME_BIN for tools like Cursor, Karma, etc.
      CHROME_BIN = chromePath;
      CHROME_PATH = chromePath;
    };
  };
}
