{
  self,
  nixpkgs,
  pkgs,
  zen-browser,
  claude-code,
  ocmonitor,
  host,
  hostModule,
  lockFile,
}:

let
  repoRoot = ../..;
  alternateUserFixture = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit zen-browser claude-code ocmonitor; };
    modules = [
      ../../modules/unfree-packages.nix
      ../../modules/validation.nix
      ../../modules/primary-user.nix
      ../../modules/dotfiles-manager.nix
      ../../modules/applications.nix
      hostModule
      ({ lib, ... }: {
        users.users = lib.mkForce {
          alice = {
            isNormalUser = true;
            home = "/srv/alice";
          };
        };
        primaryUser.name = lib.mkForce "alice";
        dotfiles = {
          enable = lib.mkForce true;
          repoPath = lib.mkForce "/srv/alice/nixos";
        };
        applications = {
          devtools = {
            ai = {
              opencode = {
                enable = lib.mkForce true;
                web.enable = lib.mkForce true;
              };
              "global-skills".enable = lib.mkForce true;
            };
            tui.ocmonitor.enable = lib.mkForce true;
          };
          games.gamemode.enable = lib.mkForce true;
        };
      })
    ];
  };
  dotfilesApiFixture = self.nixosConfigurations.${host}.extendModules {
    modules = [
      ({ lib, ... }: {
        applications = {
          browsers = {
            brave = {
              enable = lib.mkForce true;
              dotfiles.enable = lib.mkForce true;
            };
            zen-browser = {
              enable = lib.mkForce true;
              dotfiles.enable = lib.mkForce false;
            };
          };
          devtools.git = {
            enable = lib.mkForce true;
            dotfiles.enable = lib.mkForce false;
          };
          services.networking.protonvpn = {
            enable = lib.mkForce true;
            dotfiles.enable = lib.mkForce false;
          };
        };
      })
    ];
  };
  hostLock = builtins.fromJSON (builtins.readFile lockFile);
  claudeNixpkgsInput = hostLock.nodes."claude-code".inputs.nixpkgs;
  zenNixpkgsInput = hostLock.nodes."zen-browser".inputs.nixpkgs;
  claudeFollowsRoot =
    builtins.isList claudeNixpkgsInput
    && builtins.length claudeNixpkgsInput == 1
    && builtins.head claudeNixpkgsInput == "nixpkgs";
  nixpkgsNodeCount = builtins.length (
    builtins.filter (nodeName: builtins.match "nixpkgs(_[0-9]+)?" nodeName != null) (
      builtins.attrNames hostLock.nodes
    )
  );
in
{
  alternate-user = pkgs.runCommand "alternate-user-test" { } ''
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.primaryUser.name} = alice
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.dotfiles.user} = alice
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.applications.devtools.shells.fish.user} = alice
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.applications.games.gamemode.user} = alice
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.environment.sessionVariables.NIXOS_REPO} = /srv/alice/nixos
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.environment.sessionVariables.NIXOS_HOST_KEY} = \
      ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.networking.hostName}
    case ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.environment.sessionVariables.NIXOS_FLAKE_PATH} in
      *legacy-user*) echo "Flake path contains a legacy user" >&2; exit 1 ;;
      /srv/alice/nixos|/srv/alice/nixos/*) ;;
      *) echo "Flake path is outside the example repository" >&2; exit 1 ;;
    esac
    test ${
      if builtins.hasAttr "legacy-user" alternateUserFixture.config.users.users then "1" else "0"
    } = 0
    test ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.systemd.user.services.opencode-web.environment.PATH} != ""
    case ${nixpkgs.lib.escapeShellArg alternateUserFixture.config.systemd.user.services.opencode-web.environment.PATH} in
      *legacy-user*) echo "OpenCode user PATH contains a legacy user" >&2; exit 1 ;;
      *'/etc/profiles/per-user/alice/bin'*) ;;
      *) echo "OpenCode user PATH does not contain alice" >&2; exit 1 ;;
    esac
    for generated_script in \
      ${alternateUserFixture.config.system.build.dotfilesUserScript} \
      ${alternateUserFixture.config.systemd.user.services.matt-pocock-skills.serviceConfig.ExecStart} \
      ${alternateUserFixture.config.systemd.user.services.ocmonitor-directories.serviceConfig.ExecStart}; do
      hardcoded_home="/ho"
      hardcoded_home+="me/alice"
      if ${pkgs.gnugrep}/bin/grep -Eq "$hardcoded_home|legacy-user" "$generated_script"; then
        echo "$generated_script contains a hard-coded user path" >&2
        exit 1
      fi
      ${pkgs.gnugrep}/bin/grep -q '/srv/alice' "$generated_script"
    done
    for editor_settings in \
      ${repoRoot}/modules/devtools/ide/cursor/settings.json \
      ${repoRoot}/modules/devtools/ide/vscode/settings.json; do
      hardcoded_home="/ho"
      hardcoded_home+="me/alice"
      if ${pkgs.gnugrep}/bin/grep -Eq "$hardcoded_home|legacy-user" "$editor_settings"; then
        echo "$editor_settings contains a hard-coded primary-user path" >&2
        exit 1
      fi
      ${pkgs.gnugrep}/bin/grep -q 'NIXOS_FLAKE_PATH' "$editor_settings"
      ${pkgs.gnugrep}/bin/grep -q 'NIXOS_HOST_KEY' "$editor_settings"
    done
    touch "$out"
  '';

  dotfiles-option-api = pkgs.runCommand "dotfiles-option-api-test" { } ''
    test ${
      if dotfilesApiFixture.config.applications.browsers.brave.dotfiles.enable then "1" else "0"
    } = 1
    test ${
      if dotfilesApiFixture.config.applications.browsers.zen-browser.dotfiles.enable then "1" else "0"
    } = 0
    test ${if dotfilesApiFixture.config.applications.devtools.git.dotfiles.enable then "1" else "0"} = 0
    test ${
      if dotfilesApiFixture.config.applications.services.networking.protonvpn.dotfiles.enable then
        "1"
      else
        "0"
    } = 0
    test ${if builtins.hasAttr "brave" dotfilesApiFixture.config.dotfiles.modules then "1" else "0"} = 1
    test ${
      if builtins.hasAttr "zen-browser" dotfilesApiFixture.config.dotfiles.modules then "1" else "0"
    } = 0
    test ${if builtins.hasAttr "git" dotfilesApiFixture.config.dotfiles.modules then "1" else "0"} = 0
    test ${
      if builtins.hasAttr "protonvpn" dotfilesApiFixture.config.dotfiles.modules then "1" else "0"
    } = 0
    touch "$out"
  '';

  input-topology = pkgs.runCommand "input-topology-test" { } ''
    test ${if claudeFollowsRoot then "1" else "0"} = 1
    test ${if builtins.isString zenNixpkgsInput then "1" else "0"} = 1
    test ${toString nixpkgsNodeCount} = 2
    touch "$out"
  '';
}
