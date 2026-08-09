{ pkgs, nixpkgs }:

let
  repoRoot = ../..;
  dotfilesFixture = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ../../modules/dotfiles-manager.nix
      {
        system.stateVersion = "25.05";
        users.users.nixbld = {
          isNormalUser = true;
          home = "/build/dotfiles-home";
        };
        dotfiles = {
          enable = true;
          user = "nixbld";
          repoPath = "/build/dotfiles-checkout";
          modules.fixture = {
            enable = true;
            sourceDir = "tests/dotfiles-manager/fixtures";
            mappings = {
              one = {
                source = "one/settings.json";
                target = "$HOME/.config/one/settings.json";
              };
              two = {
                source = "two/settings.json";
                target = "$HOME/.config/two/settings.json";
                copyTo = "/build/dotfiles-system/settings.json";
              };
              executable = {
                source = "tool.sh";
                target = "$HOME/.local/bin/tool";
                executable = true;
              };
            };
          };
        };
      }
    ];
  };
  invalidHomeCopyFixture = dotfilesFixture.extendModules {
    modules = [
      ({ lib, ... }: {
        dotfiles.modules.fixture.mappings.two.copyTo = lib.mkForce "$HOME/.config/two/system.json";
      })
    ];
  };
  invalidHomeCopyEvaluation = builtins.tryEval invalidHomeCopyFixture.config.system.build.toplevel.drvPath;
in
{
  dotfiles-manager =
    pkgs.runCommand "dotfiles-manager-tests"
      {
        nativeBuildInputs = with pkgs; [
          bash
          coreutils
          findutils
          gnugrep
        ];
      }
      ''
        export REPO_ROOT=${repoRoot}
        bash ${../dotfiles-manager/test-user-activation.sh}
        bash ${../dotfiles-manager/test-system-copy.sh}
        touch "$out"
      '';

  dotfiles-generated-script =
    pkgs.runCommand "dotfiles-generated-script-test"
      {
        nativeBuildInputs = with pkgs; [
          coreutils
          findutils
          gnugrep
        ];
      }
      ''
        mkdir -p \
          /build/dotfiles-checkout/tests/dotfiles-manager \
          /build/dotfiles-home/.config/one \
          /build/dotfiles-home/.config/two
        cp -r ${../dotfiles-manager/fixtures} \
          /build/dotfiles-checkout/tests/dotfiles-manager/fixtures
        printf 'local one\n' > /build/dotfiles-home/.config/one/settings.json
        printf 'local two\n' > /build/dotfiles-home/.config/two/settings.json

        ${dotfilesFixture.config.system.build.dotfilesUserScript}
        test "$(find /build/dotfiles-home/.dotfiles-backups -name original -type f | wc -l)" -eq 2
        ${dotfilesFixture.config.system.build.dotfilesUserScript}
        test "$(find /build/dotfiles-home/.dotfiles-backups -name original -type f | wc -l)" -eq 2

        ${dotfilesFixture.config.system.build.dotfilesSystemScript}
        ${pkgs.gnugrep}/bin/grep -q '"fixture":"two"' /build/dotfiles-system/settings.json

        mv /build/dotfiles-checkout /build/dotfiles-checkout-away
        if ${dotfilesFixture.config.system.build.dotfilesUserScript} > unavailable.log 2>&1; then
          echo "unavailable checkout unexpectedly succeeded" >&2
          exit 1
        fi
        ${pkgs.gnugrep}/bin/grep -q 'checkout source unavailable' unavailable.log
        if ${pkgs.gnugrep}/bin/grep -q 'Dotfiles applied' unavailable.log; then
          echo "unavailable checkout claimed success" >&2
          exit 1
        fi
        touch "$out"
      '';

  dotfiles-schema = pkgs.runCommand "dotfiles-schema-test" { } ''
    test ${if invalidHomeCopyEvaluation.success then "1" else "0"} = 0
    touch "$out"
  '';
}
